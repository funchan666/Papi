import Foundation

@MainActor extension CoffeeHouse {
    var brewBook:BrewNotebook {state.brewNotebook ?? BrewNotebook()}
    func updateBrewBook(_ change:(inout BrewNotebook)->Void) {
        _ = commit {archive in var book=archive.brewNotebook ?? BrewNotebook();change(&book);archive.setBrewNotebook(book)}
    }
    func ownsRecipe(_ recipe:BrewRecipe)->Bool {
        recipe.unlockCoins==0 || (usesCloudWallet ? (cloudWallet?.recipes.contains(recipe.id) ?? false):brewBook.unlockedRecipes.contains(recipe.id))
    }
    @discardableResult func unlockRecipe(_ recipe:BrewRecipe)->Bool {
        guard !usesCloudWallet else{return false}
        guard !ownsRecipe(recipe) else{return true}
        guard state.coinBalance>=recipe.unlockCoins else{insufficientCoins(cost:recipe.unlockCoins);return false}
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            guard !book.unlockedRecipes.contains(recipe.id) else{return}
            archive.coinBalance -= recipe.unlockCoins
            archive.coinMovements.insert(.init(id:"recipe-"+recipe.id,delta:-recipe.unlockCoins,reason:recipe.title),at:0)
            book.unlockedRecipes.insert(recipe.id);archive.setBrewNotebook(book)
        }
    }
    func startPour(_ recipe:BrewRecipe)->Bool {
        guard ownsRecipe(recipe) else{return false}
        guard brewBook.activePour==nil else{inform("A pour is already on the bench","Return to your current pour, or save it before starting another.");return false}
        let draft=brewBook.draft
        let lot=draft.coffeeLot.trimmingCharacters(in:.whitespacesAndNewlines)
        guard !lot.isEmpty else{inform("Name these beans","Add a roaster or coffee name so you can recognise this cup later.");return false}
        guard (8...40).contains(draft.doseGrams) else{return false}
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            book.activePour = .init(recipeID:recipe.id,coffeeLot:String(lot.prefix(100)),doseGrams:draft.doseGrams,grindNote:String(draft.grindNote.prefix(100)),baselineCupID:draft.baselineCupID)
            archive.setBrewNotebook(book)
        }
    }
    func togglePourClock() {
        guard var pour=brewBook.activePour else{return}
        if pour.resumedAt != nil {pour.accumulatedSeconds=pour.elapsed(at:Date());pour.resumedAt=nil}
        else {pour.resumedAt=Date()}
        updateBrewBook{$0.activePour=pour}
    }
    @discardableResult func saveBrew()->Bool {
        guard let pour=brewBook.activePour,let recipe=BrewRecipe.recipe(pour.recipeID) else{return false}
        guard let seconds=Int(exactly:pour.elapsed(at:Date()).rounded(.down)),seconds>0 else{return false}
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            guard !book.cups.contains(where:{$0.id==pour.id}) else{return}
            book.cups.insert(.init(id:pour.id,recipeID:recipe.id,coffeeLot:pour.coffeeLot,doseGrams:pour.doseGrams,hotWaterGrams:recipe.water(for:pour.doseGrams),iceGrams:recipe.ice(for:pour.doseGrams),waterCelsius:recipe.waterCelsius,grindNote:pour.grindNote,elapsedSeconds:seconds,baselineCupID:pour.baselineCupID),at:0)
            if let baseline=pour.baselineCupID,book.cups.contains(where:{$0.id==baseline}) {book.firstComparisonCup=baseline;book.secondComparisonCup=pour.id}
            book.draft.baselineCupID=nil
            book.activePour=nil;archive.setBrewNotebook(book)
        }
    }
    func discardPour() {updateBrewBook{$0.activePour=nil}}
    func prepareRebrew(from cupID:UUID)->Bool {
        guard brewBook.activePour==nil else {inform("A pour is already on the bench","Return to your current pour, or save it before starting another.");return false}
        guard let cup=brewBook.cups.first(where:{$0.id==cupID}) else{return false}
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            book.draft = .init(coffeeLot:cup.coffeeLot,doseGrams:cup.doseGrams,grindNote:cup.grindNote,baselineCupID:cup.id)
            archive.setBrewNotebook(book)
        }
    }
    func saveImpression(_ impression:CupImpression,for cupID:UUID)->Bool {
        guard (1...5).contains(impression.sweetness),(1...5).contains(impression.brightness),(1...5).contains(impression.body),impression.aromaNote.count<=1000 else{return false}
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            guard let index=book.cups.firstIndex(where:{$0.id==cupID}) else{return}
            var tasted=impression;tasted.hasBeenTasted=true;book.cups[index].impression=tasted;book.impressionDrafts.removeValue(forKey:cupID.uuidString);archive.setBrewNotebook(book)
        }
    }
    func saveFlight(preference:CuppingFlight.Preference)->Bool {
        let book=brewBook
        guard let first=book.firstComparisonCup,let second=book.secondComparisonCup,first != second,
              let firstCup=book.cups.first(where:{$0.id==first && $0.impression.hasBeenTasted}),let secondCup=book.cups.first(where:{$0.id==second && $0.impression.hasBeenTasted}) else {
            inform("Two cups, two tasting notes","Choose two different cups and add tasting notes to each before saving a comparison.");return false
        }
        return commit {archive in
            var book=archive.brewNotebook ?? BrewNotebook()
            book.flights.insert(.init(firstCupID:first,secondCupID:second,preferredCup:preference,tastingNote:String(book.comparisonNote.prefix(1000)),recordedChanges:firstCup.recipeChanges(comparedWith:secondCup),firstImpression:firstCup.impression,secondImpression:secondCup.impression),at:0)
            book.firstComparisonCup=nil;book.secondComparisonCup=nil;book.comparisonNote="";book.comparisonPreference = .undecided;archive.setBrewNotebook(book)
        }
    }
    func deleteBrew(_ id:UUID) {
        updateBrewBook {book in
            book.cups.removeAll{$0.id==id};book.flights.removeAll{$0.firstCupID==id || $0.secondCupID==id}
            book.impressionDrafts.removeValue(forKey:id.uuidString)
            if book.draft.baselineCupID==id {book.draft.baselineCupID=nil}
            if book.activePour?.baselineCupID==id {book.activePour?.baselineCupID=nil}
            for index in book.cups.indices where book.cups[index].baselineCupID==id {book.cups[index].baselineCupID=nil}
            if book.firstComparisonCup==id {book.firstComparisonCup=nil}
            if book.secondComparisonCup==id {book.secondComparisonCup=nil}
        }
    }
}
