import AirspaceCore
import SwiftUI

/// First run: pick a location while a live preview fills in.
struct WelcomeView: View {
    @Bindable var model: AppModel
    @State private var query = ""
    @Environment(\.dismiss) private var dismiss

    private let previewSize = CGSize(width: 560, height: 330)

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            VStack(alignment: .leading, spacing: 6) {
                Text("AIRSPACE")
                    .font(.system(size: 26, weight: .semibold).width(.expanded))
                    .tracking(6)
                Text("A live map of the sky above you, as your wallpaper.")
                    .font(.title3)
                    .foregroundStyle(.secondary)
            }

            preview

            VStack(alignment: .leading, spacing: 10) {
                Button {
                    model.useSystemLocation()
                } label: {
                    Label("Use My Location", systemImage: "location.fill").frame(maxWidth: .infinity)
                }
                .controlSize(.large)

                HStack {
                    TextField("Zip code, city, or coordinates", text: $query)
                        .textFieldStyle(.roundedBorder)
                        .controlSize(.large)
                        .onSubmit { model.setPlace(query: query) }
                    Button("Preview") { model.setPlace(query: query) }
                        .controlSize(.large)
                        .disabled(query.trimmingCharacters(in: .whitespaces).isEmpty)
                }
                if let message = model.locationMessage {
                    Text(message).font(.callout).foregroundStyle(.orange)
                }
            }

            HStack {
                Text("No account or API key needed: positions come from adsb.lol and adsb.fi, free community networks. You can change everything later from the \(Image(systemName: "airplane.circle.fill")) menu.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer()
                Button("Set as Wallpaper") {
                    model.completeOnboarding(with: model.settings.location)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
                .controlSize(.large)
                .disabled(model.center == nil)
            }
        }
        .padding(28)
        .frame(width: previewSize.width + 56)
        .onAppear { model.beginPreview() }
    }

    private var preview: some View {
        AirspaceView(model: model, size: CGSize(width: previewSize.width * 2, height: previewSize.height * 2), insets: EdgeInsets())
            .scaleEffect(0.5, anchor: .topLeading)
            .frame(width: previewSize.width, height: previewSize.height, alignment: .topLeading)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous).strokeBorder(.separator))
            .overlay {
                if model.center == nil {
                    VStack(spacing: 8) {
                        if model.isResolvingLocation { ProgressView() }
                        Text(model.isResolvingLocation ? "Finding you…" : "Choose a location to preview")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                    }
                }
            }
    }
}
