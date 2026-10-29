import Foundation

struct PourCheckpoint:Identifiable,Codable {
    let id:Int
    let cue:String
    let elapsedSeconds:Int
    let cumulativeWaterFraction:Double
}
struct BrewRecipe:Identifiable,Codable {
    let id:String
    let title:String
    let brewer:String
    let story:String
    let coffeeGrams:Int
    let hotWaterGrams:Int
    let iceGrams:Int
    let waterCelsius:Int
    let drawdownSeconds:Int
    let unlockCoins:Int
    let checkpoints:[PourCheckpoint]
    func water(for dose:Int)->Int {Int((Double(hotWaterGrams)*Double(dose)/Double(coffeeGrams)).rounded())}
    func ice(for dose:Int)->Int {Int((Double(iceGrams)*Double(dose)/Double(coffeeGrams)).rounded())}
    static var collection:[BrewRecipe] {CoffeeCollection.cloudRecipes() ?? []}
    static func recipe(_ id:String)->BrewRecipe? {collection.first{$0.id==id}}
}
struct CupImpression:Codable {
    var sweetness=3
    var brightness=3
    var body=3
    var aromaNote=""
    var hasBeenTasted=false
}
struct BrewDraft:Codable {
    var coffeeLot=""
    var doseGrams=18
    var grindNote=""
    var baselineCupID:UUID? = nil
}
struct PourSession:Identifiable,Codable {
    var id=UUID()
    let recipeID:String
    let coffeeLot:String
    let doseGrams:Int
    let grindNote:String
    var baselineCupID:UUID? = nil
    var accumulatedSeconds:TimeInterval=0
    var resumedAt:Date? = Date()
    var startedAt=Date()
    func elapsed(at now:Date)->TimeInterval {
        max(0,accumulatedSeconds + (resumedAt.map{max(0,now.timeIntervalSince($0))} ?? 0))
    }
}
struct BrewRecord:Identifiable,Codable {
    let id:UUID
    let recipeID:String
    let coffeeLot:String
    let doseGrams:Int
    let hotWaterGrams:Int
    let iceGrams:Int
    let waterCelsius:Int
    let grindNote:String
    let elapsedSeconds:Int
    var brewedAt=Date()
    var impression=CupImpression()
    var baselineCupID:UUID? = nil
    func recipeChanges(comparedWith other:BrewRecord)->[BrewVariableChange] {
        let settings:[(BrewVariable,String,String)] = [
            (.coffeeLot,coffeeLot,other.coffeeLot),(.brewer,BrewRecipe.recipe(recipeID)?.brewer ?? "",BrewRecipe.recipe(other.recipeID)?.brewer ?? ""),(.coffeeDose,"\(doseGrams) g","\(other.doseGrams) g"),
            (.hotWater,"\(hotWaterGrams) g","\(other.hotWaterGrams) g"),(.ice,"\(iceGrams) g","\(other.iceGrams) g"),
            (.waterTemperature,"\(waterCelsius) °C","\(other.waterCelsius) °C"),(.grindSetting,grindNote,other.grindNote)
        ]
        return settings.compactMap {setting -> BrewVariableChange? in
            let (variable,first,second)=setting
            let normalise:(String)->String = {$0.trimmingCharacters(in:.whitespacesAndNewlines).folding(options:[.caseInsensitive,.diacriticInsensitive],locale:Locale(identifier:"en_US_POSIX"))}
            return normalise(first)==normalise(second) ? nil:.init(variable:variable,firstSetting:first,secondSetting:second)
        }
    }
}
enum BrewVariable:String,Codable,Equatable {
    case coffeeLot,brewer,coffeeDose,hotWater,ice,waterTemperature,grindSetting
    var title:String {switch self {
    case .coffeeLot:return "Coffee name"
    case .brewer:return "Brewer"
    case .coffeeDose:return "Coffee dose"
    case .hotWater:return "Hot water"
    case .ice:return "Ice"
    case .waterTemperature:return "Water temperature"
    case .grindSetting:return "Grind setting"
    }}
}
struct BrewVariableChange:Identifiable,Codable {
    let variable:BrewVariable
    let firstSetting:String
    let secondSetting:String
    var id:String {variable.rawValue}
}
struct CuppingFlight:Identifiable,Codable {
    enum Preference:String,Codable,CaseIterable,Hashable {case first,second,both,undecided}
    var id=UUID()
    let firstCupID:UUID
    let secondCupID:UUID
    let preferredCup:Preference
    let tastingNote:String
    var tastedAt=Date()
    var recordedChanges:[BrewVariableChange]? = nil
    var firstImpression:CupImpression? = nil
    var secondImpression:CupImpression? = nil
}
struct CoffeeRatioPlan:Codable {
    var coffeeGrams=18
    var partsWater=16
}
struct BrewNotebook:Codable {
    var draft=BrewDraft()
    var activePour:PourSession? = nil
    var unlockedRecipes:Set<String> = []
    var cups:[BrewRecord] = []
    var flights:[CuppingFlight] = []
    var impressionDrafts:[String:CupImpression] = [:]
    var firstComparisonCup:UUID? = nil
    var secondComparisonCup:UUID? = nil
    var comparisonNote=""
    var comparisonPreference:CuppingFlight.Preference = .undecided
    var ratioPlan:CoffeeRatioPlan? = nil
    enum CodingKeys:String,CodingKey {case draft,activePour,unlockedRecipes,cups,flights,impressionDrafts,firstComparisonCup,secondComparisonCup,comparisonNote,comparisonPreference,ratioPlan}
    init() {}
    init(from decoder:Decoder) throws {
        let saved=try decoder.container(keyedBy:CodingKeys.self)
        draft=try saved.decodeIfPresent(BrewDraft.self,forKey:.draft) ?? BrewDraft()
        activePour=try saved.decodeIfPresent(PourSession.self,forKey:.activePour)
        unlockedRecipes=try saved.decodeIfPresent(Set<String>.self,forKey:.unlockedRecipes) ?? []
        cups=try saved.decodeIfPresent([BrewRecord].self,forKey:.cups) ?? []
        flights=try saved.decodeIfPresent([CuppingFlight].self,forKey:.flights) ?? []
        impressionDrafts=try saved.decodeIfPresent([String:CupImpression].self,forKey:.impressionDrafts) ?? [:]
        firstComparisonCup=try saved.decodeIfPresent(UUID.self,forKey:.firstComparisonCup)
        secondComparisonCup=try saved.decodeIfPresent(UUID.self,forKey:.secondComparisonCup)
        comparisonNote=try saved.decodeIfPresent(String.self,forKey:.comparisonNote) ?? ""
        comparisonPreference=try saved.decodeIfPresent(CuppingFlight.Preference.self,forKey:.comparisonPreference) ?? .undecided
        ratioPlan=try saved.decodeIfPresent(CoffeeRatioPlan.self,forKey:.ratioPlan)
    }
}
