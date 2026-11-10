import AVFoundation
import ImageIO
import Testing
import UIKit
@testable import Bookplate

struct ImageCompressorTests {
    private func png(width: Int, height: Int) -> Data {
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        return UIGraphicsImageRenderer(size: CGSize(width: width, height: height), format: format).pngData { context in
            UIColor.systemTeal.setFill()
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
    }

    private func info(_ data: Data) -> (width: Int, height: Int, type: String)? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil),
              let props = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = props[kCGImagePropertyPixelWidth] as? Int,
              let height = props[kCGImagePropertyPixelHeight] as? Int,
              let type = CGImageSourceGetType(source) as String?
        else { return nil }
        return (width, height, type)
    }

    @Test func largePhotoShrinksToMaxSideAsJPEG() throws {
        let output = try #require(ImageCompressor.jpeg(from: png(width: 2000, height: 3000)))
        let result = try #require(info(output))
        #expect(result.height == 1000)
        #expect((666...667).contains(result.width))
        #expect(result.type == "public.jpeg")
    }

    @Test func wideImageCapsTheLongerSide() throws {
        let output = try #require(ImageCompressor.jpeg(from: png(width: 2400, height: 1200)))
        let result = try #require(info(output))
        #expect(result.width == 1000)
        #expect(result.height == 500)
    }

    @Test func smallImageIsNotUpscaled() throws {
        let output = try #require(ImageCompressor.jpeg(from: png(width: 300, height: 450)))
        let result = try #require(info(output))
        #expect(result.width == 300)
        #expect(result.height == 450)
        #expect(result.type == "public.jpeg")
    }

    @Test func outputIsSmallerThanALargeOriginal() throws {
        let original = png(width: 3000, height: 4000)
        let output = try #require(ImageCompressor.jpeg(from: original))
        #expect(output.count < original.count)
    }

    @Test func nonImageDataReturnsNil() {
        #expect(ImageCompressor.jpeg(from: Data("not an image".utf8)) == nil)
        #expect(ImageCompressor.jpeg(from: Data()) == nil)
    }

    @Test func cameraAccessMapping() {
        #expect(CameraAccess.resolve(hasCamera: false, status: .authorized) == .unavailable)
        #expect(CameraAccess.resolve(hasCamera: true, status: .authorized) == .allowed)
        #expect(CameraAccess.resolve(hasCamera: true, status: .notDetermined) == .notDetermined)
        #expect(CameraAccess.resolve(hasCamera: true, status: .denied) == .denied)
        #expect(CameraAccess.resolve(hasCamera: true, status: .restricted) == .denied)
    }
}
