import Foundation
import CoreGraphics
import ImageIO

/// Opt-in synthetic files for the real Files picker. Never reads health data or credentials.
enum BackupUIFixtures {
    static func write(to folder: URL) throws {
        let fm = FileManager.default
        try fm.createDirectory(at: folder, withIntermediateDirectories: true)
        let random = try FileHandle(forReadingFrom: URL(fileURLWithPath: "/dev/urandom"))
        defer { try? random.close() }
        let side = 1536, count = side * side * 4
        var pixels = Data()
        while pixels.count < count { pixels.append(try random.read(upToCount:count - pixels.count)!) }
        let image = CGImage(width:side,height:side,bitsPerComponent:8,bitsPerPixel:32,bytesPerRow:side*4,space:CGColorSpaceCreateDeviceRGB(),bitmapInfo:CGBitmapInfo(rawValue:CGImageAlphaInfo.noneSkipLast.rawValue),provider:CGDataProvider(data:pixels as CFData)!,decode:nil,shouldInterpolate:false,intent:.defaultIntent)!
        let bytes = NSMutableData()
        let destination = CGImageDestinationCreateWithData(bytes,"public.jpeg" as CFString,1,nil)!
        CGImageDestinationAddImage(destination,image,[kCGImageDestinationLossyCompressionQuality:0.90] as CFDictionary)
        guard CGImageDestinationFinalize(destination) else { throw BackupError.invalid }
        let photo = bytes as Data
        guard photo.count < BackupArchive.maxPhotoBytes else { throw BackupError.invalid }
        let privatePhoto = folder.appendingPathComponent("synthetic-photo.jpg")
        try photo.write(to:privatePhoto)
        defer { try? fm.removeItem(at:privatePhoto) }
        var profile = UserProfile.default; profile.name = "Synthetic transfer profile"
        var document = HealthDocument(id:"transfer-plan", title:"Synthetic transfer plan",kind:.plan,body:"Synthetic backup fixture, for testing only.",steps:[PlanStep(title:"Take a short walk")],source:"Synthetic fixture")
        document.includeInAssistant = true
        var snapshot = BackupSnapshot(profile:profile,goals:.init(),habits:[],sleep:[],meals:[Meal(id:"transfer-meal",type:.lunch,items:[],photoID:"transfer-photo")],workouts:[],water:[HydrationLog(id:"transfer-water",ml:375)],conversations:[],symptoms:[SymptomEntry(id:"transfer-symptom",name:"Synthetic shoulder note",location:"Shoulder",severity:2,note:"Synthetic test data",triggers:[])],checkIns:[],documents:[document],importedDays:[],imports:[],personalContext:.init(),photos:[:])
        let password = "Synthetic backup passphrase 42"
        let small = folder.appendingPathComponent("Lumen-backup-encrypted.lumenbackup")
        try BackupPackage.write(snapshot,photos:["transfer-photo":privatePhoto],password:password,to:small)
        var legacy = snapshot; legacy.photos = ["transfer-photo":photo]
        try BackupArchive.make(legacy).write(to:folder.appendingPathComponent("Lumen-backup-legacy.json"))
        var corrupted = try Data(contentsOf:small); corrupted[corrupted.count/2] ^= 1
        try corrupted.write(to:folder.appendingPathComponent("Lumen-backup-damaged.lumenbackup"))
        let copies = 1152 * 1024 * 1024 / photo.count + 2
        snapshot.meals = (0..<copies).map { Meal(id:"large-transfer-meal-\($0)",type:.lunch,items:[],photoID:"large-transfer-photo-\($0)") }
        let lastHour = Date()
        snapshot.water = (0..<100_000).map { HydrationLog(id:"large-transfer-water-\($0)",date:lastHour.addingTimeInterval(-Double($0 + 1) * 3600),ml:125) }
        let photos = Dictionary(uniqueKeysWithValues:(0..<copies).map { ("large-transfer-photo-\($0)",privatePhoto) })
        let large = folder.appendingPathComponent("Lumen-backup-large.lumenbackup")
        try BackupPackage.write(snapshot,photos:photos,password:password,to:large)
        let size = try large.resourceValues(forKeys:[.fileSizeKey]).fileSize!
        guard size > BackupArchive.maxBytes else { throw BackupError.invalid }
        print("Synthetic backup fixtures ready: \(copies) valid JPEG photos, \(size) encrypted bytes; 100,000 water logs; password: Synthetic backup passphrase 42")
    }
}
