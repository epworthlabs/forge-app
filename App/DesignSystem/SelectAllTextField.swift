import SwiftUI
import UIKit

/// Feature request — "when I double tap the field when searching for foods, adding my own foods,
/// or any other text based field (not numbers) it should select all text in that field." Plain
/// SwiftUI `TextField` has no text-selection API to hook this to before iOS 17's `TextSelection`
/// (this app targets 16), and a double-tap on a stock `UITextField` only selects the *word* under
/// it (standard iOS text-editing behavior) — there's no built-in gesture for "select everything."
/// This wraps `UITextField` directly and adds that gesture, as a drop-in replacement for `TextField`
/// on every plain-text (non-numeric-keypad) field in the app.
struct SelectAllTextField: UIViewRepresentable {
    @Binding var text: String
    var placeholder: String = ""
    var font: UIFont = ForgeType.bodyUIFont
    var textColor: UIColor = UIColor(ForgeColors.ink)
    var autocapitalization: UITextAutocapitalizationType = .sentences
    var autocorrection: UITextAutocorrectionType = .default
    var returnKeyType: UIReturnKeyType = .default
    var onCommit: (() -> Void)?

    func makeUIView(context: Context) -> UITextField {
        let field = UITextField()
        field.delegate = context.coordinator
        field.addTarget(context.coordinator, action: #selector(Coordinator.textChanged), for: .editingChanged)
        field.setContentHuggingPriority(.defaultLow, for: .horizontal)
        field.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let doubleTap = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleDoubleTap))
        doubleTap.numberOfTapsRequired = 2
        field.addGestureRecognizer(doubleTap)
        return field
    }

    func updateUIView(_ uiView: UITextField, context: Context) {
        if uiView.text != text { uiView.text = text }
        uiView.placeholder = placeholder
        uiView.font = font
        uiView.textColor = textColor
        uiView.autocapitalizationType = autocapitalization
        uiView.autocorrectionType = autocorrection
        uiView.returnKeyType = returnKeyType
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UITextFieldDelegate {
        var parent: SelectAllTextField
        init(_ parent: SelectAllTextField) { self.parent = parent }

        @objc func textChanged(_ sender: UITextField) {
            parent.text = sender.text ?? ""
        }

        @objc func handleDoubleTap(_ gesture: UITapGestureRecognizer) {
            guard let field = gesture.view as? UITextField else { return }
            if !field.isFirstResponder { field.becomeFirstResponder() }
            field.selectAll(nil)
        }

        func textFieldShouldReturn(_ textField: UITextField) -> Bool {
            textField.resignFirstResponder()
            parent.onCommit?()
            return true
        }
    }
}
