import Foundation
import UIKit

class TrackingImageView: UIView {
    
    var image: UIImage!
    var polyRects = [TrackedPolyRect]()

    var imageAreaRect = CGRect.zero
    var aPath = UIBezierPath()


    let dashedPhase = CGFloat(0.0)
    let dashedLinesLengths: [CGFloat] = [4.0, 2.0]

    // Rubber-banding setup
    var rubberbandingStart = CGPoint.zero
    var rubberbandingVector = CGPoint.zero
    var rubberbandingRect: CGRect {
        let pt1 = self.rubberbandingStart
        let pt2 = CGPoint(x: self.rubberbandingStart.x + self.rubberbandingVector.x, y: self.rubberbandingStart.y + self.rubberbandingVector.y)
        let rect = CGRect(x: min(pt1.x, pt2.x), y: min(pt1.y, pt2.y), width: abs(pt1.x - pt2.x), height: abs(pt1.y - pt2.y))
        
        return rect
    }

    var rubberbandingRectNormalized: CGRect {
        guard imageAreaRect.size.width > 0 && imageAreaRect.size.height > 0 else {
            return CGRect.zero
        }
        var rect = rubberbandingRect
        
        // Make it relative to imageAreaRect
        rect.origin.x = (rect.origin.x - self.imageAreaRect.origin.x) / self.imageAreaRect.size.width
        rect.origin.y = (rect.origin.y - self.imageAreaRect.origin.y) / self.imageAreaRect.size.height
        rect.size.width /= self.imageAreaRect.size.width
        rect.size.height /= self.imageAreaRect.size.height
        // Adjust to Vision.framework input requrement - origin at LLC
        rect.origin.y = 1.0 - rect.origin.y - rect.size.height
        
        return rect
    }

    func isPointWithinDrawingArea(_ locationInView: CGPoint) -> Bool {
        return self.imageAreaRect.contains(locationInView)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        self.setNeedsDisplay()
    }
    

    override func draw(_ rect: CGRect) {
        let ctx = UIGraphicsGetCurrentContext()!

        ctx.saveGState()

        ctx.clear(rect)
        ctx.setFillColor(red: 0.0, green: 0.0, blue: 0.0, alpha: 0.0)
        ctx.setLineWidth(2.0)

        // Draw a frame
        guard let newImage = scaleImage(to: rect.size) else {
            return
        }
        newImage.draw(at: self.imageAreaRect.origin)

        // Draw rubberbanding rectangle, if available
        if self.rubberbandingRect != CGRect.zero {
            ctx.setStrokeColor(UIColor.blue.cgColor)
            ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            ctx.stroke(self.rubberbandingRect)
        }

        var lastCenter: CGPoint? = nil
        // Draw rects and calculate centers
        for polyRect in self.polyRects {
            ctx.setStrokeColor(polyRect.color.cgColor)
            switch polyRect.style {
            case .solid:
                ctx.setLineDash(phase: dashedPhase, lengths: [])
            case .dashed:
                ctx.setLineDash(phase: dashedPhase, lengths: dashedLinesLengths)
            }
            let cornerPoints = polyRect.cornerPoints
            var totalX: CGFloat = 0
            var totalY: CGFloat = 0
            var count: CGFloat = CGFloat(cornerPoints.count)

            var previous = scale(cornerPoint: cornerPoints.last!, toImageViewPointInViewRect: rect)
            for cornerPoint in cornerPoints {
                let current = scale(cornerPoint: cornerPoint, toImageViewPointInViewRect: rect)
                ctx.move(to: previous)
                ctx.addLine(to: current)
                previous = current
                totalX += current.x
                totalY += current.y
            }
            ctx.strokePath()

            let center = CGPoint(x: totalX / count, y: totalY / count)
            if let last = lastCenter {
                // Draw line from the last center to the current center
                ctx.setStrokeColor(UIColor.red.cgColor) // Set the color for the center line
                ctx.move(to: last)
                ctx.addLine(to: center)
                ctx.strokePath()
            }
            lastCenter = center
        }

        ctx.restoreGState()
    }



    private func scaleImage(to viewSize: CGSize) -> UIImage? {
        guard self.image != nil && self.image.size != CGSize.zero else {
            return nil
        }
        
        self.imageAreaRect = CGRect.zero

        // There are two possible cases to fully fit self.image into the the ImageTrackingView area:
        // Option 1) image.width = view.width ==> image.height <= view.height
        // Option 2) image.height = view.height ==> image.width <= view.width
        let imageAspectRatio = self.image.size.width / self.image.size.height

        // Check if we're in Option 1) case and initialize self.imageAreaRect accordingly
        let imageSizeOption1 = CGSize(width: viewSize.width, height: floor(viewSize.width / imageAspectRatio))
        if imageSizeOption1.height <= viewSize.height {
            let imageX: CGFloat = 0
            let imageY = floor((viewSize.height - imageSizeOption1.height) / 2.0)
            self.imageAreaRect = CGRect(x: imageX,
                                        y: imageY,
                                        width: imageSizeOption1.width,
                                        height: imageSizeOption1.height)
        }

        if self.imageAreaRect == CGRect.zero {
            // Check if we're in Option 2) case if Option 1) didn't work out and initialize imageAreaRect accordingly
            let imageSizeOption2 = CGSize(width: floor(viewSize.height * imageAspectRatio), height: viewSize.height)
            if imageSizeOption2.width <= viewSize.width {
                let imageX = floor((viewSize.width - imageSizeOption2.width) / 2.0)
                let imageY: CGFloat = 0
                self.imageAreaRect = CGRect(x: imageX,
                                            y: imageY,
                                            width: imageSizeOption2.width,
                                            height: imageSizeOption2.height)
            }
        }

        // In next line, pass 0.0 to use the current device's pixel scaling factor (and thus account for Retina resolution).
        // Pass 1.0 to force exact pixel size.
        UIGraphicsBeginImageContextWithOptions(self.imageAreaRect.size, false, 0.0)
        self.image.draw(in: CGRect(x: 0.0, y: 0.0, width: self.imageAreaRect.size.width, height: self.imageAreaRect.size.height))
        
        let newImage = UIGraphicsGetImageFromCurrentImageContext()
        UIGraphicsEndImageContext()

        return newImage
    }
    
    private func scale(cornerPoint point: CGPoint, toImageViewPointInViewRect viewRect: CGRect) -> CGPoint {
        // Adjust bBox from Vision.framework coordinate system (origin at LLC) to imageView coordinate system (origin at ULC)
        let pointY = 1.0 - point.y
        let scaleFactor = self.imageAreaRect.size
        
        return CGPoint(x: point.x * scaleFactor.width + self.imageAreaRect.origin.x, y: pointY * scaleFactor.height + self.imageAreaRect.origin.y)
    }
}
