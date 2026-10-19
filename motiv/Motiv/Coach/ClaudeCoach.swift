import CoreGraphics
import Foundation

/// Antwort von Claude: der beste Bildausschnitt in Anteilen des Bildes (Ursprung oben links) plus Tipp.
struct ClaudeSuggestion: Decodable {
    let subject: String
    let tip: String
    let x: Double
    let y: Double
    let width: Double
    let height: Double

    var unitRect: CGRect {
        CGRect(x: x, y: y, width: width, height: height).standardized.intersection(.unit)
    }
}

struct ClaudeModelOption: Identifiable {
    let id: String
    let name: String
}

enum ClaudeCoachError: LocalizedError {
    case missingKey
    case http(Int, String)
    case refused
    case badAnswer

    var errorDescription: String? {
        switch self {
        case .missingKey: return "Kein API-Schlüssel – trag ihn in den Einstellungen ein."
        case .http(let code, let message): return "Claude-Fehler \(code): \(message)"
        case .refused: return "Claude hat die Anfrage abgelehnt."
        case .badAnswer: return "Claudes Antwort war unvollständig – versuch's nochmal."
        }
    }
}

/// Smart-Scan: schickt ein verkleinertes Sucherbild an die Claude-API (Messages API, raw HTTP –
/// für Swift gibt es kein offizielles SDK) und bekommt Ausschnitt + Tipp als JSON zurück.
enum ClaudeCoach {
    static let defaultModel = "claude-opus-5-5"
    static let models = [
        ClaudeModelOption(id: "claude-opus-5-5", name: "Opus 5.5 – beste Vorschläge"),
        ClaudeModelOption(id: "claude-sonnet-5-5", name: "Sonnet 5.5 – Mittelweg"),
        ClaudeModelOption(id: "claude-haiku-5-5", name: "Haiku 5.5 – schnell & günstig"),
    ]

    static func suggest(jpeg: Data, aspect: AspectRatio, apiKey: String, model: String) async throws -> ClaudeSuggestion {
        guard !apiKey.isEmpty else { throw ClaudeCoachError.missingKey }

        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!)
        request.httpMethod = "POST"
        request.timeoutInterval = 90
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")

        // Lehnt ein Modell ab, springt serverseitig ein passendes Ersatzmodell ein.
        // Haiku hat keinen serverseitigen Fallback.
        let usesFallback = !model.contains("haiku")
        if usesFallback {
            request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")
        }

        let image: [String: Any] = [
            "type": "image",
            "source": ["type": "base64", "media_type": "image/jpeg", "data": jpeg.base64EncodedString()],
        ]
        let text: [String: Any] = ["type": "text", "text": prompt(for: aspect)]
        let message: [String: Any] = ["role": "user", "content": [image, text]]
        let format: [String: Any] = ["type": "json_schema", "schema": schema]
        let outputConfig: [String: Any] = ["effort": "low", "format": format]
        var body: [String: Any] = [
            "model": model,
            "max_tokens": 4000,
            "output_config": outputConfig,
            "messages": [message],
        ]
        if usesFallback { body["fallbacks"] = "default" }
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard status == 200 else {
            let message = (try? JSONDecoder().decode(APIErrorBody.self, from: data))?.error.message ?? "Unbekannter Fehler"
            throw ClaudeCoachError.http(status, message)
        }

        let reply = try JSONDecoder().decode(MessageReply.self, from: data)
        if reply.stop_reason == "refusal" { throw ClaudeCoachError.refused }
        guard let text = reply.content.first(where: { $0.type == "text" })?.text,
              let suggestion = try? JSONDecoder().decode(ClaudeSuggestion.self, from: Data(text.utf8)),
              suggestion.unitRect.width > 0.02, suggestion.unitRect.height > 0.02 else {
            throw ClaudeCoachError.badAnswer
        }
        return suggestion
    }

    private static func prompt(for aspect: AspectRatio) -> String {
        """
        Du bist ein erfahrener Fotograf und coachst jemanden live an der Handykamera. \
        Das Bild ist der aktuelle Sucher im Hochformat 3:4.

        Finde den Ausschnitt dieser Szene, der das stärkste Foto ergibt – oft ein Detail, eine Struktur, \
        ein Lichtspiel oder ein klares Motiv, nicht einfach alles.
        Der Ausschnitt soll im echten Bild ungefähr das Seitenverhältnis \(aspect.rawValue) (Breite:Höhe) haben.

        Gib den Ausschnitt in Anteilen des Bildes an, gemessen von links oben: x und y sind die linke obere Ecke, \
        width und height die Größe, alles zwischen 0 und 1.
        subject: das Motiv in 1–3 Wörtern auf Deutsch.
        tip: ein kurzer Tipp auf Deutsch (höchstens 12 Wörter), wie das Foto noch besser wird – Winkel, Licht oder Abstand.
        """
    }

    private static let schema: [String: Any] = [
        "type": "object",
        "properties": [
            "subject": ["type": "string"],
            "tip": ["type": "string"],
            "x": ["type": "number"],
            "y": ["type": "number"],
            "width": ["type": "number"],
            "height": ["type": "number"],
        ],
        "required": ["subject", "tip", "x", "y", "width", "height"],
        "additionalProperties": false,
    ]

    private struct MessageReply: Decodable {
        struct Block: Decodable {
            let type: String
            let text: String?
        }

        let content: [Block]
        let stop_reason: String?
    }

    private struct APIErrorBody: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}
