/*
See LICENSE folder for this sample’s licensing information.

Abstract:
The app's photo capture delegate object.
*/

import AVFoundation
import Photos
import UIKit
import CoreImage

class PhotoCaptureProcessor: NSObject {
    private(set) var requestedPhotoSettings: AVCapturePhotoSettings
    
    private let willCapturePhotoAnimation: () -> Void
    
    private let livePhotoCaptureHandler: (Bool) -> Void
    
    lazy var context = CIContext()
    
    private let completionHandler: (PhotoCaptureProcessor) -> Void
    
    private let photoProcessingHandler: (Bool) -> Void
    
    private var photoData: Data?
    
    private var livePhotoCompanionMovieURL: URL?
    
    private var portraitEffectsMatteData: Data?
    
    private var semanticSegmentationMatteDataArray = [Data]()
    private var maxPhotoProcessingTime: CMTime?

    // Save the location of captured photos
    var location: CLLocation?

    init(with requestedPhotoSettings: AVCapturePhotoSettings,
         willCapturePhotoAnimation: @escaping () -> Void,
         livePhotoCaptureHandler: @escaping (Bool) -> Void,
         completionHandler: @escaping (PhotoCaptureProcessor) -> Void,
         photoProcessingHandler: @escaping (Bool) -> Void) {
        self.requestedPhotoSettings = requestedPhotoSettings
        self.willCapturePhotoAnimation = willCapturePhotoAnimation
        self.livePhotoCaptureHandler = livePhotoCaptureHandler
        self.completionHandler = completionHandler
        self.photoProcessingHandler = photoProcessingHandler
    }
    
    private func didFinish() {
        if let livePhotoCompanionMoviePath = livePhotoCompanionMovieURL?.path {
            if FileManager.default.fileExists(atPath: livePhotoCompanionMoviePath) {
                do {
                    try FileManager.default.removeItem(atPath: livePhotoCompanionMoviePath)
                } catch {
                    print("Could not remove file at url: \(livePhotoCompanionMoviePath)")
                }
            }
        }
        
        completionHandler(self)
    }
}

extension PhotoCaptureProcessor: AVCapturePhotoCaptureDelegate {
    /*
     This extension adopts all of the AVCapturePhotoCaptureDelegate protocol methods.
     */
    
    /// - Tag: WillBeginCapture
    func photoOutput(_ output: AVCapturePhotoOutput, willBeginCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        if resolvedSettings.livePhotoMovieDimensions.width > 0 && resolvedSettings.livePhotoMovieDimensions.height > 0 {
            livePhotoCaptureHandler(true)
        }
        maxPhotoProcessingTime = resolvedSettings.photoProcessingTimeRange.start + resolvedSettings.photoProcessingTimeRange.duration
    }
    
    /// - Tag: WillCapturePhoto
    func photoOutput(_ output: AVCapturePhotoOutput, willCapturePhotoFor resolvedSettings: AVCaptureResolvedPhotoSettings) {
        willCapturePhotoAnimation()
        
        guard let maxPhotoProcessingTime = maxPhotoProcessingTime else {
            return
        }
        
        // Show a spinner if processing time exceeds one second.
        let oneSecond = CMTime(seconds: 1, preferredTimescale: 1)
        if maxPhotoProcessingTime > oneSecond {
            photoProcessingHandler(true)
        }
    }
    
    func handleMatteData(_ photo: AVCapturePhoto, ssmType: AVSemanticSegmentationMatte.MatteType) {
        
        // Find the semantic segmentation matte image for the specified type.
        guard var segmentationMatte = photo.semanticSegmentationMatte(for: ssmType) else { return }
        
        // Retrieve the photo orientation and apply it to the matte image.
        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
            let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            // Apply the Exif orientation to the matte image.
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
        }
        
        var imageOption: CIImageOption!
        
        // Switch on the AVSemanticSegmentationMatteType value.
        switch ssmType {
        case .hair:
            imageOption = .auxiliarySemanticSegmentationHairMatte
        case .skin:
            imageOption = .auxiliarySemanticSegmentationSkinMatte
        case .teeth:
            imageOption = .auxiliarySemanticSegmentationTeethMatte
        case .glasses:
            imageOption = .auxiliarySemanticSegmentationGlassesMatte
        default:
            print("This semantic segmentation type is not supported!")
            return
        }
        
        
        let inputImage = CIImage(cgImage: photo.cgImageRepresentation()!)
        // Retrieve the photo orientation and apply it to the matte image.
        var rect = CGRect(x: 0, y: 0, width: inputImage.extent.width, height: inputImage.extent.height)
        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
            let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
            // Apply the Exif orientation to the matte image.
            segmentationMatte = segmentationMatte.applyingExifOrientation(exifOrientation)
            inputImage.oriented(exifOrientation)
        }
        //var inputPixelBuffer = inputImage.pixelBuffer
        rect = CGRect(x: 0, y: 0, width: inputImage.extent.width, height: inputImage.extent.height)
        UIGraphicsBeginImageContext(rect.size)
        let cgContext = UIGraphicsGetCurrentContext()
        cgContext?.setFillColor(UIColor.blue.cgColor)
        cgContext?.fill(rect)
        guard let bgImage = UIGraphicsGetImageFromCurrentImageContext() else {
            UIGraphicsEndImageContext()
            return
        }
        UIGraphicsEndImageContext()
        let background = CIImage(cgImage: bgImage.cgImage!)
        let mask = CIImage(cvImageBuffer: segmentationMatte.mattingImage)
        // Retrieve the photo orientation and apply it to the matte image.
//        if let orientation = photo.metadata[String(kCGImagePropertyOrientation)] as? UInt32,
//            let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
//            // Apply the Exif orientation to the matte image.
//            background = background.applyingExifOrientation(exifOrientation)
//        }
//
        let maskScaleX = inputImage.extent.width / mask.extent.width
        let maskScaleY = inputImage.extent.width / mask.extent.width
        let maskScaled = mask.transformed(by: __CGAffineTransformMake(maskScaleX, 0, 0, maskScaleY, 0, 0))
        
        let backgroundScaleX = inputImage.extent.width / background.extent.width
        let backgroundScaleY = inputImage.extent.height / background.extent.height
        let backgroundScaled = background.transformed(by: __CGAffineTransformMake(backgroundScaleX, 0, 0, backgroundScaleY, 0, 0))
        // blendWithBlueMaskFilter
        let blendFilter = CIFilter(name: "CIBlendWithMask")!
        blendFilter.setValue(inputImage, forKey: "inputImage")
        blendFilter.setValue(backgroundScaled, forKey: "inputBackgroundImage")
        blendFilter.setValue(maskScaled, forKey: "inputMaskImage")
        
        guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return }
        
        if let blendedImage = blendFilter.outputImage {
            let ciContext = CIContext(options: nil)
            //let filteredImageRef = ciContext.createCGImage(blendedImage, from: blendedImage.extent)
            //let maskDisplayRef = ciContext.createCGImage(maskScaled, from: maskScaled.extent)
            guard let imageData = ciContext.heifRepresentation(of: blendedImage,
                                                             format: .RGBA8,
                                                             colorSpace: perceptualColorSpace) else { return }
            
            // Add the image data to the SSM data array for writing to the photo library.
            semanticSegmentationMatteDataArray.append(imageData)
            return
        }
        
        

        
        // Create a new CIImage from the matte's underlying CVPixelBuffer.
        let ciImage = CIImage( cvImageBuffer: segmentationMatte.mattingImage,
                               options: [imageOption: true,
                                         .colorSpace: perceptualColorSpace])
        
        // Get the HEIF representation of this image.
        guard let imageData = context.heifRepresentation(of: ciImage,
                                                         format: .RGBA8,
                                                         colorSpace: perceptualColorSpace,
                                                         options: [.depthImage: ciImage]) else { return }
        
        // Add the image data to the SSM data array for writing to the photo library.
        semanticSegmentationMatteDataArray.append(imageData)
    }
    
    /// - Tag: DidFinishProcessingPhoto
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingPhoto photo: AVCapturePhoto, error: Error?) {
        photoProcessingHandler(false)

        if let error = error {
            print("Error capturing photo: \(error)")
            return
        } else {
            photoData = photo.fileDataRepresentation()
        }
        // A portrait effects matte gets generated only if AVFoundation detects a face.
        if var portraitEffectsMatte = photo.portraitEffectsMatte {

            let portraitEffectsMattePixelBuffer = portraitEffectsMatte.mattingImage
            let portraitEffectsMatteImage = CIImage( cvImageBuffer: portraitEffectsMattePixelBuffer, options: [ .auxiliaryPortraitEffectsMatte: true ] )
            var inputImage = CIImage(cgImage: photo.cgImageRepresentation()!)
            if let orientation = photo.metadata[ String(kCGImagePropertyOrientation) ] as? UInt32,
               let exifOrientation = CGImagePropertyOrientation(rawValue: orientation) {
                portraitEffectsMatte = portraitEffectsMatte.applyingExifOrientation(exifOrientation)
                inputImage = inputImage.oriented(exifOrientation)
            }
            
            let mask = CIImage(cvImageBuffer: portraitEffectsMatte.mattingImage)
            let rect = CGRect(x: 0, y: 0, width: inputImage.extent.width, height: inputImage.extent.height)
            UIGraphicsBeginImageContext(rect.size)
            let cgContext = UIGraphicsGetCurrentContext()
            cgContext?.setFillColor(UIColor.blue.cgColor)
            cgContext?.fill(rect)
            guard let bgImage = UIGraphicsGetImageFromCurrentImageContext() else {
                UIGraphicsEndImageContext()
                return
            }
            UIGraphicsEndImageContext()
            let background = CIImage(cgImage: bgImage.cgImage!)
            let maskScaleX = inputImage.extent.width / mask.extent.width
            let maskScaleY = inputImage.extent.width / mask.extent.width
            let maskScaled = mask.transformed(by: __CGAffineTransformMake(maskScaleX, 0, 0, maskScaleY, 0, 0))
            
            let backgroundScaleX = inputImage.extent.width / background.extent.width
            let backgroundScaleY = inputImage.extent.height / background.extent.height
            let backgroundScaled = background.transformed(by: __CGAffineTransformMake(backgroundScaleX, 0, 0, backgroundScaleY, 0, 0))
            // blendWithBlueMaskFilter
            let blendFilter = CIFilter(name: "CIBlendWithMask")!
            blendFilter.setValue(inputImage, forKey: "inputImage")
            blendFilter.setValue(backgroundScaled, forKey: "inputBackgroundImage")
            blendFilter.setValue(maskScaled, forKey: "inputMaskImage")
            
            
            guard let perceptualColorSpace = CGColorSpace(name: CGColorSpace.sRGB) else {
                portraitEffectsMatteData = nil
                return
            }
            
            if let blendedImage = blendFilter.outputImage {
                let ciContext = CIContext(options: nil)
                //let filteredImageRef = ciContext.createCGImage(blendedImage, from: blendedImage.extent)
                //let maskDisplayRef = ciContext.createCGImage(maskScaled, from: maskScaled.extent)
                guard let imageData = ciContext.heifRepresentation(of: blendedImage,
                                                                 format: .RGBA8,
                                                                 colorSpace: perceptualColorSpace) else { return }
                
                // Add the image data to the SSM data array for writing to the photo library.
                //semanticSegmentationMatteDataArray.append(imageData)
                portraitEffectsMatteData = imageData
                return
            } else {
                portraitEffectsMatteData = context.heifRepresentation(of: portraitEffectsMatteImage,
                                                                      format: .RGBA8,
                                                                      colorSpace: perceptualColorSpace,
                                                                      options: [.portraitEffectsMatteImage: portraitEffectsMatteImage])
            }
            

        } else {
            portraitEffectsMatteData = nil
        }
        
        for semanticSegmentationType in output.enabledSemanticSegmentationMatteTypes {
            handleMatteData(photo, ssmType: semanticSegmentationType)
        }
    }
    
    /// - Tag: DidFinishRecordingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishRecordingLivePhotoMovieForEventualFileAt outputFileURL: URL, resolvedSettings: AVCaptureResolvedPhotoSettings) {
        livePhotoCaptureHandler(false)
    }
    
    /// - Tag: DidFinishProcessingLive
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishProcessingLivePhotoToMovieFileAt outputFileURL: URL, duration: CMTime, photoDisplayTime: CMTime, resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if error != nil {
            print("Error processing Live Photo companion movie: \(String(describing: error))")
            return
        }
        livePhotoCompanionMovieURL = outputFileURL
    }
    
    /// - Tag: DidFinishCapture
    func photoOutput(_ output: AVCapturePhotoOutput, didFinishCaptureFor resolvedSettings: AVCaptureResolvedPhotoSettings, error: Error?) {
        if let error = error {
            print("Error capturing photo: \(error)")
            didFinish()
            return
        }

        guard let photoData = photoData else {
            print("No photo data resource")
            didFinish()
            return
        }

        PHPhotoLibrary.requestAuthorization { status in
            if status == .authorized {
                PHPhotoLibrary.shared().performChanges({
                    let options = PHAssetResourceCreationOptions()
                    let creationRequest = PHAssetCreationRequest.forAsset()
                    options.uniformTypeIdentifier = self.requestedPhotoSettings.processedFileType.map { $0.rawValue }
                    creationRequest.addResource(with: .photo, data: photoData, options: options)
                    
                    // Specify the location the photo was taken
                    creationRequest.location = self.location
                    
                    if let livePhotoCompanionMovieURL = self.livePhotoCompanionMovieURL {
                        let livePhotoCompanionMovieFileOptions = PHAssetResourceCreationOptions()
                        livePhotoCompanionMovieFileOptions.shouldMoveFile = true
                        creationRequest.addResource(with: .pairedVideo,
                                                    fileURL: livePhotoCompanionMovieURL,
                                                    options: livePhotoCompanionMovieFileOptions)
                    }
                    
                    // Save Portrait Effects Matte to Photos Library only if it was generated
                    if let portraitEffectsMatteData = self.portraitEffectsMatteData {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: portraitEffectsMatteData,
                                                    options: nil)
                    }
                    // Save Portrait Effects Matte to Photos Library only if it was generated
                    for semanticSegmentationMatteData in self.semanticSegmentationMatteDataArray {
                        let creationRequest = PHAssetCreationRequest.forAsset()
                        creationRequest.addResource(with: .photo,
                                                    data: semanticSegmentationMatteData,
                                                    options: nil)
                    }
                    
                }, completionHandler: { _, error in
                    if let error = error {
                        print("Error occurred while saving photo to photo library: \(error)")
                    }
                    
                    self.didFinish()
                }
                )
            } else {
                self.didFinish()
            }
        }
    }
}
