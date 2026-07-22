import Foundation

guard CommandLine.arguments.count == 3 else { exit(2) }
let iconset = URL(fileURLWithPath: CommandLine.arguments[1], isDirectory: true)
let outputURL = URL(fileURLWithPath: CommandLine.arguments[2])

let entries: [(String, String)] = [
    ("icp4", "icon_16x16.png"),
    ("icp5", "icon_32x32.png"),
    ("icp6", "icon_32x32@2x.png"),
    ("ic07", "icon_128x128.png"),
    ("ic08", "icon_256x256.png"),
    ("ic09", "icon_512x512.png"),
    ("ic10", "icon_512x512@2x.png")
]

func bigEndianData(_ value: UInt32) -> Data {
    var bigEndian = value.bigEndian
    return Data(bytes: &bigEndian, count: MemoryLayout<UInt32>.size)
}

var body = Data()
for (type, filename) in entries {
    let png = try Data(contentsOf: iconset.appendingPathComponent(filename))
    body.append(type.data(using: .ascii)!)
    body.append(bigEndianData(UInt32(png.count + 8)))
    body.append(png)
}

var icns = Data("icns".utf8)
icns.append(bigEndianData(UInt32(body.count + 8)))
icns.append(body)
try icns.write(to: outputURL, options: .atomic)
