import SpriteKit

/// The global art style. Leaves read it today; eventually other mechanics will too (own charter).
enum AutumnStyle: String, Codable, CaseIterable {
    case retro, realistic
    var label: String { self == .retro ? "Retro" : "Realistic" }
}

/// Loads the autumn sprite atlases and slices them into per-frame textures, from `atlas.json`.
///
/// Atlas frames are in top-left pixel coordinates; SpriteKit's texture space is bottom-left and
/// normalised, so each frame rect is converted and flipped in `slice`.
final class AutumnAssets {
    struct StyleAssets {
        /// Front variants (realistic: 6 leaves) or turn frames (retro: 8-frame swivel).
        let leafFrames: [SKTexture]
        /// Side / curled / folded resting poses for the pile.
        let pileFrames: [SKTexture]
        /// Height/width of each pile pose, taken from the atlas rects (not the texture, whose
        /// reported sub-size is unreliable).
        let pileAspects: [CGFloat]
        let branches: BranchPieces
    }

    /// The canopy, cut into a left corner, a top strip (tiled across wide screens) and a right corner,
    /// so the art is drawn near its native scale instead of being stretched to the screen width.
    struct BranchPieces {
        let left, top, right: BranchPiece
    }

    struct BranchPiece {
        let texture: SKTexture
        /// Source pixels.
        let size: CGSize
        /// Points on foliage, normalised with a top-left origin: where shaken-off leaves start.
        let leafSpots: [CGPoint]
        /// Per source column, the lowest row (from the top) with foliage; nil where the column is empty.
        let bottoms: [Int?]
    }

    private let dir: URL
    private var cache: [AutumnStyle: StyleAssets] = [:]
    private let atlas: Atlas

    init(dir: URL) {
        self.dir = dir
        let data = try! Data(contentsOf: dir.appendingPathComponent("atlas.json"))
        atlas = try! JSONDecoder().decode(Atlas.self, from: data)
    }

    /// The `assets` directory inside the app bundle, where `bundle.sh` copies the atlas.
    static var bundled: AutumnAssets {
        AutumnAssets(dir: Bundle.main.resourceURL!.appendingPathComponent("assets"))
    }

    func assets(for style: AutumnStyle) -> StyleAssets {
        if let hit = cache[style] { return hit }
        let s = atlas.styles[style.rawValue]!
        let nearest = s.filter == "nearest"
        let leaves = texture(s.leaves, nearest: nearest)
        let pile = texture(s.pile, nearest: nearest)
        let built = StyleAssets(
            leafFrames: s.frames.map { slice($0, from: leaves, atlas: s.atlasSize, nearest: nearest) },
            pileFrames: s.pileFrames.map { slice($0, from: pile, atlas: s.pileAtlasSize, nearest: nearest) },
            pileAspects: s.pileFrames.map { CGFloat($0.h) / CGFloat($0.w) },
            branches: branchPieces(s.branches, nearest: nearest))
        cache[style] = built
        return built
    }

    private func texture(_ path: String, nearest: Bool) -> SKTexture {
        let name = (path as NSString).lastPathComponent
        let image = NSImage(contentsOf: dir.appendingPathComponent(name))!
        let texture = SKTexture(image: image)
        texture.filteringMode = nearest ? .nearest : .linear
        return texture
    }

    private func branchPieces(_ path: String, nearest: Bool) -> BranchPieces {
        let name = (path as NSString).lastPathComponent
        let image = NSImage(contentsOf: dir.appendingPathComponent(name))!
            .cgImage(forProposedRect: nil, context: nil, hints: nil)!
        let h = Int((CGFloat(image.height) * 0.53).rounded(.up)), fade = 32
        let cuts = cutColumns(image, height: h, band: fade)
        func piece(_ x0: Int, _ x1: Int, fadeLeft: Bool, fadeRight: Bool) -> BranchPiece {
            let w = x1 - x0
            let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            ctx.draw(image.cropping(to: CGRect(x: x0, y: 0, width: w, height: h))!,
                     in: CGRect(x: 0, y: 0, width: w, height: h))
            let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
            dropStrays(px, width: w, height: h, cutLeft: fadeLeft, cutRight: fadeRight)
            // Fade the cut edges (premultiplied, so every channel scales); screen-facing edges stay solid.
            for x in 0..<w {
                var k: CGFloat = 1
                if fadeLeft, x < fade { k = CGFloat(x) / CGFloat(fade) }
                if fadeRight, x >= w - fade { k = min(k, CGFloat(w - 1 - x) / CGFloat(fade)) }
                guard k < 1 else { continue }
                for y in 0..<h { for c in 0..<4 { px[(y * w + x) * 4 + c] = UInt8(CGFloat(px[(y * w + x) * 4 + c]) * k) } }
            }
            var spots: [CGPoint] = []
            for _ in 0..<4000 where spots.count < 300 {
                let x = Int.random(in: fade..<max(fade + 1, w - fade)), y = Int.random(in: h / 5..<h)
                if px[(y * w + x) * 4 + 3] > 220 { spots.append(CGPoint(x: CGFloat(x) / CGFloat(w), y: CGFloat(y) / CGFloat(h))) }
            }
            let texture = SKTexture(cgImage: ctx.makeImage()!)
            texture.filteringMode = nearest ? .nearest : .linear
            let bottoms = (0..<w).map { x in (0..<h).last { px[($0 * w + x) * 4 + 3] > 64 } }
            return BranchPiece(texture: texture, size: CGSize(width: w, height: h), leafSpots: spots, bottoms: bottoms)
        }
        return BranchPieces(left: piece(0, cuts.left, fadeLeft: false, fadeRight: true),
                            top: piece(cuts.left, cuts.right, fadeLeft: true, fadeRight: true),
                            right: piece(cuts.right, image.width, fadeLeft: true, fadeRight: false))
    }

    /// Where to cut the corners from the top strip: the column near 32 % / 68 % of the width whose
    /// fade band crosses the least foliage, so the fades soften branches rather than slice a leaf.
    /// Foliage in the top rows counts for less, since branches entering from the top are cut anyway.
    private func cutColumns(_ image: CGImage, height h: Int, band: Int) -> (left: Int, right: Int) {
        let w = image.width
        let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                            space: CGColorSpaceCreateDeviceRGB(),
                            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        ctx.draw(image.cropping(to: CGRect(x: 0, y: 0, width: w, height: h))!, in: CGRect(x: 0, y: 0, width: w, height: h))
        let px = ctx.data!.assumingMemoryBound(to: UInt8.self)
        var column = [Double](repeating: 0, count: w)
        for y in 0..<h {
            let weight = y < h * 15 / 100 ? 0.2 : 1
            for x in 0..<w { column[x] += Double(px[(y * w + x) * 4 + 3]) * weight }
        }
        func quietest(near fraction: Double) -> Int {
            let centre = Int(Double(w) * fraction), reach = w * 8 / 100
            return (centre - reach...centre + reach).min { a, b in
                column[max(0, a - band)..<min(w, a + band)].reduce(0, +) < column[max(0, b - band)..<min(w, b + band)].reduce(0, +)
            }!
        }
        return (quietest(near: 0.32), quietest(near: 0.68))
    }

    /// Clears foliage the cut sliced off a neighbouring piece: anything touching a cut edge that
    /// doesn't hang from the top of the image. Left in, it shows as a faded half-leaf, repeated
    /// on every tile of the top strip.
    private func dropStrays(_ px: UnsafeMutablePointer<UInt8>, width w: Int, height h: Int, cutLeft: Bool, cutRight: Bool) {
        var label = [Int32](repeating: 0, count: w * h)
        var next: Int32 = 0
        var stack: [Int] = []
        for start in 0..<(w * h) where label[start] == 0 && px[start * 4 + 3] > 0 {
            next += 1
            var members: [Int] = [], touchesCut = false, hangsFromTop = false
            label[start] = next; stack.append(start)
            while let i = stack.popLast() {
                members.append(i)
                let x = i % w, y = i / w
                if (cutLeft && x == 0) || (cutRight && x == w - 1) { touchesCut = true }
                if y == 0 { hangsFromTop = true }
                for (nx, ny) in [(x - 1, y), (x + 1, y), (x, y - 1), (x, y + 1)]
                    where nx >= 0 && nx < w && ny >= 0 && ny < h {
                    let j = ny * w + nx
                    if label[j] == 0 && px[j * 4 + 3] > 0 { label[j] = next; stack.append(j) }
                }
            }
            if touchesCut && !hangsFromTop {
                for i in members { for c in 0..<4 { px[i * 4 + c] = 0 } }
            }
        }
    }

    private func slice(_ f: Atlas.Frame, from parent: SKTexture, atlas size: [Int], nearest: Bool) -> SKTexture {
        let w = CGFloat(size[0]), h = CGFloat(size[1])
        let rect = CGRect(x: CGFloat(f.x) / w, y: 1 - CGFloat(f.y + f.h) / h,
                          width: CGFloat(f.w) / w, height: CGFloat(f.h) / h)
        let sub = SKTexture(rect: rect, in: parent)
        sub.filteringMode = nearest ? .nearest : .linear
        return sub
    }

    // MARK: - atlas.json shape (only the frame geometry is read; sim params live in Leaves)

    private struct Atlas: Decodable {
        struct Frame: Decodable { let x, y, w, h: Int }
        struct Style: Decodable {
            let leaves: String
            let branches: String
            let atlasSize: [Int]
            let frames: [Frame]
            let filter: String
            let pile: String
            let pileAtlasSize: [Int]
            let pileFrames: [Frame]
        }
        let styles: [String: Style]
    }
}
