#if os(iOS)
import AVFoundation
import SwiftUI
import UIKit

/// Whether "Take Photo" can be offered, and what tapping it should do.
enum CameraAccess: Equatable {
    /// The device has no camera (e.g. the simulator): hide "Take Photo".
    case unavailable
    case allowed
    /// First use: open the camera and let iOS ask.
    case notDetermined
    /// Denied or restricted: explain and offer Settings.
    case denied

    static func current() -> CameraAccess {
        resolve(hasCamera: UIImagePickerController.isSourceTypeAvailable(.camera),
                status: AVCaptureDevice.authorizationStatus(for: .video))
    }

    static func resolve(hasCamera: Bool, status: AVAuthorizationStatus) -> CameraAccess {
        guard hasCamera else { return .unavailable }
        switch status {
        case .authorized: return .allowed
        case .notDetermined: return .notDetermined
        default: return .denied
        }
    }

    /// Asks iOS for access when needed. True when the camera can be opened.
    static func request() async -> Bool {
        switch current() {
        case .allowed: true
        case .notDetermined: await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .unavailable: false
        }
    }
}

/// The system camera, returning the captured photo (or nil if cancelled).
struct CameraPicker: UIViewControllerRepresentable {
    let onFinish: (UIImage?) -> Void

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ picker: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(onFinish: onFinish) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onFinish: (UIImage?) -> Void
        init(onFinish: @escaping (UIImage?) -> Void) { self.onFinish = onFinish }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            onFinish(info[.originalImage] as? UIImage)
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            onFinish(nil)
        }
    }
}
#endif
