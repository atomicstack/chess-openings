import SwiftUI

/// Custom yes/no confirmation overlay. Rendered as a full-screen layer
/// above the host view via `.overlay { ... }` — the host owns the
/// presented state and toggles it inside `withAnimation { ... }` for
/// smooth in/out transitions.
struct ConfirmationModal: View {
    let title: String
    let message: String
    let confirmLabel: String
    let confirmRole: ButtonRole?
    let cancelLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void

    init(
        title: String,
        message: String = "",
        confirmLabel: String,
        confirmRole: ButtonRole? = nil,
        cancelLabel: String = "cancel",
        onConfirm: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.title = title
        self.message = message
        self.confirmLabel = confirmLabel
        self.confirmRole = confirmRole
        self.cancelLabel = cancelLabel
        self.onConfirm = onConfirm
        self.onCancel = onCancel
    }

    var body: some View {
        ZStack {
            // Dimmed backdrop — tap anywhere outside the card to cancel.
            Color.black.opacity(0.45)
                .ignoresSafeArea()
                .contentShape(Rectangle())
                .onTapGesture(perform: onCancel)

            VStack(spacing: 14) {
                Text(title)
                    .font(.headline)
                    .multilineTextAlignment(.center)
                if !message.isEmpty {
                    Text(message)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                HStack(spacing: 12) {
                    Button(cancelLabel, action: onCancel)
                        .buttonStyle(.bordered)
                        .frame(maxWidth: .infinity)
                    Button(confirmLabel, role: confirmRole, action: onConfirm)
                        .buttonStyle(.borderedProminent)
                        .frame(maxWidth: .infinity)
                }
                .padding(.top, 4)
            }
            .padding(24)
            .frame(maxWidth: 320)
            .background(
                RoundedRectangle(cornerRadius: 18)
                    .fill(.regularMaterial)
            )
            .shadow(color: .black.opacity(0.25), radius: 18, x: 0, y: 4)
            .padding(.horizontal, 32)
        }
        .transition(
            .opacity.combined(with: .scale(scale: 0.85))
        )
    }
}
