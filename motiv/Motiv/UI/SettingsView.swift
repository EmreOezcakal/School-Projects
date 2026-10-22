import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @AppStorage("showGrid") private var showGrid = true
    @AppStorage("showLevel") private var showLevel = true
    @AppStorage("autoSave") private var autoSave = true
    @AppStorage("smartScan") private var smartScan = false
    @AppStorage("claudeModel") private var claudeModel = ClaudeCoach.defaultModel
    @AppStorage("maxResolution") private var maxResolution = true
    @AppStorage("saveJPEG") private var saveJPEG = false
    @State private var apiKey = Keychain.read(Keychain.apiKeyAccount) ?? ""

    var body: some View {
        NavigationStack {
            Form {
                Section("Sucher") {
                    Toggle("Drittel-Raster", isOn: $showGrid)
                    Toggle("Wasserwaage", isOn: $showLevel)
                    Toggle("Fotos automatisch sichern", isOn: $autoSave)
                }

                Section {
                    Picker("Auflösung", selection: $maxResolution) {
                        Text("Maximal").tag(true)
                        Text("12 MP").tag(false)
                    }
                    Toggle("Als JPEG statt HEIF sichern", isOn: $saveJPEG)
                } header: {
                    Text("Fotoqualität")
                } footer: {
                    Text("""
                    „Maximal“ nutzt die volle Sensorauflösung deines iPhones (bei neueren Pro-Modellen bis 48 MP, \
                    bei .5x und wenig Licht oft 12 MP). Nach dem Auslösen zeigt Motiv kurz an, wie viele Megapixel \
                    das Foto hat. 3:4 behält das ganze Sensorbild und die Originaldatei; 9:16, 4:5 und 1:1 schneiden zu. \
                    HEIF ist bei gleicher Qualität halb so groß; JPEG öffnet jeder Windows-PC ohne Zusatzprogramm.
                    """)
                }

                Section {
                    Toggle("✦ nutzt Smart-Scan mit Claude", isOn: $smartScan)
                    SecureField("API-Schlüssel (sk-ant-…)", text: $apiKey)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                    Picker("Modell", selection: $claudeModel) {
                        ForEach(ClaudeCoach.models) { option in
                            Text(option.name).tag(option.id)
                        }
                    }
                } header: {
                    Text("KI-Coach")
                } footer: {
                    Text("""
                    Ohne Smart-Scan sucht Motiv das Motiv direkt auf dem iPhone – kostenlos und offline. \
                    Mit Smart-Scan schickt ✦ ein verkleinertes Sucherbild an Claude und bekommt Ausschnitt \
                    und Tipp zurück; das kostet pro Scan etwas Guthaben auf deinem Anthropic-Konto \
                    (Opus am meisten, Haiku am wenigsten). Lang drücken auf ✦ nutzt jeweils den anderen Modus.
                    """)
                }

                Section("Bedienung") {
                    Label("✦ tippen: Motiv suchen, dann dem gelben Rahmen folgen", systemImage: "sparkles")
                    Label("Kritzel-Symbol: eigenen Rahmen ziehen", systemImage: "scribble.variable")
                    Label("Tippen im Sucher: Fokus, zwei Finger: Zoom", systemImage: "hand.tap")
                }
                .font(.footnote)
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Fertig") { dismiss() }
                }
            }
        }
        // Auch beim Wegwischen des Blatts sichern
        .onDisappear {
            Keychain.save(apiKey.trimmingCharacters(in: .whitespacesAndNewlines), for: Keychain.apiKeyAccount)
        }
    }
}
