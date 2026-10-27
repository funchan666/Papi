import Foundation

/// Stable aliases keep earlier journal, bookmark, avatar and draft references readable.
enum CoffeeArtwork {
    static let aliases:[String:String] = [
        "coffee00":"corner-latte",
        "coffee01":"breakfast-tray",
        "coffee02":"window-americano",
        "coffee03":"canal-coffee",
        "coffee04":"croissant-table",
        "coffee05":"round-cafe-table",
        "coffee06":"pastry-ritual",
        "coffee07":"handheld-cold-brew",
        "coffee08":"garden-coffee-seat",
        "coffee09":"home-espresso-corner",
        "coffee10":"sunlit-cup",
        "coffee11":"two-iced-lattes",
        "coffee12":"marbled-latte",
        "coffee13":"courtyard-brunch",
        "coffee14":"matcha-and-cookie",
        "coffee15":"glasshouse-cafe",
        "coffee16":"coffee-and-dates",
        "coffee17":"rose-front-cafe",
        "coffee30":"street-espresso",
        "person00":"portrait-clara",
        "person01":"portrait-jun",
        "person02":"portrait-kai",
        "person03":"portrait-theo",
        "person04":"portrait-elise",
        "person05":"portrait-mateo",
        "person06":"portrait-ren",
        "person07":"portrait-dae",
        "coffeeVideo00":"ghost-latte-art",
        "coffeeVideo01":"rosetta-practice",
        "coffeeVideo02":"cafe-company-portrait",
        "coffeeVideo03":"window-seat-journey",
        "coffeeVideo04":"iced-espresso-glass",
        "coffeeVideo05":"bar-counter-iced-latte",
        "coffeeVideo06":"blue-cup-pour",
        "coffeeVideo07":"caramel-swirl-glass",
        "coffeeVideo08":"heart-latte-workshop",
        "coffeeVideo09":"moka-orange-peel",
        "coffeeVideo10":"evening-city-company",
        "coffeeVideo11":"tulip-latte-pour",
        "coffeeVideo12":"city-cafe-walk",
        "coffeeVideo13":"espresso-on-off",
        "coffeeVideo14":"stirred-caramel-latte",
        "coffeeVideo15":"citrus-iced-coffee",
        "coffeeVideo16":"cappuccino-rosetta",
        "coffeeVideo17":"spiral-dessert-coffee",
        "coffeeVideo18":"grinder-to-espresso",
        "coffeeVideo19":"iced-milk-rosetta",
        "coffeeVideo20":"coffee-over-ice",
    ]
    static func canonical(_ reference:String)->String {aliases[reference] ?? reference}
    static let photoNames:[Int:String] = [
        0:"corner-latte",
        1:"breakfast-tray",
        2:"window-americano",
        3:"canal-coffee",
        4:"croissant-table",
        5:"round-cafe-table",
        6:"pastry-ritual",
        7:"handheld-cold-brew",
        8:"garden-coffee-seat",
        9:"home-espresso-corner",
        10:"sunlit-cup",
        11:"two-iced-lattes",
        12:"marbled-latte",
        13:"courtyard-brunch",
        14:"matcha-and-cookie",
        15:"glasshouse-cafe",
        16:"coffee-and-dates",
        17:"rose-front-cafe",
        30:"street-espresso"
    ]
    static let portraits = ["portrait-clara","portrait-jun","portrait-kai","portrait-theo","portrait-elise","portrait-mateo","portrait-ren","portrait-dae"]
    static let filmNames:[Int:String] = [
        0:"ghost-latte-art",
        1:"rosetta-practice",
        2:"cafe-company-portrait",
        3:"window-seat-journey",
        4:"iced-espresso-glass",
        5:"bar-counter-iced-latte",
        6:"blue-cup-pour",
        7:"caramel-swirl-glass",
        8:"heart-latte-workshop",
        9:"moka-orange-peel",
        10:"evening-city-company",
        11:"tulip-latte-pour",
        12:"city-cafe-walk",
        13:"espresso-on-off",
        14:"stirred-caramel-latte",
        15:"citrus-iced-coffee",
        16:"cappuccino-rosetta",
        17:"spiral-dessert-coffee",
        18:"grinder-to-espresso",
        19:"iced-milk-rosetta",
        20:"coffee-over-ice",
    ]
    static func isFilm(_ reference:String)->Bool {CoffeeCollection.entry(reference)?.kind == "film"}
}

struct CoffeeCollectionAsset:Decodable {
    let asset:String
    let kind:String
    let path:String
    let usage:String
    let memberID:String?
    let displayName:String?
    let bio:String?
}
/// An explicit catalog keeps cloud filenames out of saved guest records.
enum CoffeeCollection {
    private struct Catalog:Decodable {let baseURL:String;let items:[CoffeeCollectionAsset]}
    private static let catalog:Catalog? = {
        guard let url=Bundle.main.url(forResource:"CoffeeCollection",withExtension:"json",subdirectory:"Media"),
              let data=try? Data(contentsOf:url) else{return nil}
        return try? JSONDecoder().decode(Catalog.self,from:data)
    }()
    static var assets:[CoffeeCollectionAsset] {catalog?.items ?? []}
    private static let byName=Dictionary(uniqueKeysWithValues:assets.map{($0.asset,$0)})
    static func entry(_ reference:String)->CoffeeCollectionAsset? {byName[CoffeeArtwork.canonical(reference)]}
    static func url(_ reference:String)->URL? {
        guard let item=entry(reference),let base=catalog?.baseURL,
              base=="https://pub-6ba5fcb7fe264001a73e75d43c95636c.r2.dev",
              item.path.hasPrefix(item.kind=="film" ? "vv/":"pp/"),
              !item.path.contains(".."),item.path.split(separator:"/").count==2 else{return nil}
        return URL(string:base+"/"+item.path)
    }
    static var additionalPeople:[CoffeeMember] {
        assets.compactMap {item in
            guard item.usage=="profile",let id=item.memberID,!id.hasPrefix("preview-member-"),let name=item.displayName,let bio=item.bio else{return nil}
            return CoffeeMember(id:id,name:name,portrait:item.asset,bio:bio)
        }
    }
}
