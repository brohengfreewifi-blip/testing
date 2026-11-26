import SwiftUI

struct CheatsView: View {
    @ObservedObject var session: GameSession
    @State private var gold = "1000"
    @State private var itemId = "1"
    @State private var itemQty = "1"
    @State private var varId = "1"
    @State private var varVal = "0"
    @State private var swId = "1"
    @State private var swOn = true
    @State private var actorId = "1"
    @State private var level = "99"
    @State private var status: String?

    var body: some View {
        Form {
            Section("Gold") {
                TextField("Amount (negative to remove)", text: $gold).keyboardType(.numbersAndPunctuation)
                Button("Add gold") { go("$gameParty.gainGold(n); return 'ok';", ["n": num(gold)]) }
            }
            Section("Items") {
                TextField("Item ID", text: $itemId).keyboardType(.numberPad)
                TextField("Quantity", text: $itemQty).keyboardType(.numberPad)
                Button("Add item") {
                    go("var it=$dataItems[id]; if(!it) return 'No such item'; $gameParty.gainItem(it,n); return 'ok';",
                       ["id": num(itemId), "n": num(itemQty)])
                }
            }
            Section("Variables and switches") {
                TextField("Variable ID", text: $varId).keyboardType(.numberPad)
                TextField("Value", text: $varVal).keyboardType(.numbersAndPunctuation)
                Button("Set variable") { go("$gameVariables.setValue(id,v); return 'ok';", ["id": num(varId), "v": num(varVal)]) }
                TextField("Switch ID", text: $swId).keyboardType(.numberPad)
                Toggle("On", isOn: $swOn)
                Button("Set switch") { go("$gameSwitches.setValue(id,on); return 'ok';", ["id": num(swId), "on": swOn]) }
            }
            Section("Party") {
                Button("Fully heal party") { go("$gameParty.members().forEach(function(a){a.recoverAll();}); return 'ok';", [:]) }
                TextField("Actor ID", text: $actorId).keyboardType(.numberPad)
                Button("Add actor to party") { go("$gameParty.addActor(id); return 'ok';", ["id": num(actorId)]) }
                TextField("Level", text: $level).keyboardType(.numberPad)
                Button("Set actor level") {
                    go("var a=$gameActors.actor(id); if(!a) return 'No such actor'; a.changeLevel(lv,false); return 'ok';",
                       ["id": num(actorId), "lv": num(level)])
                }
            }
            if let s = status { Section { Text(s).font(.footnote) } }
        }
        .navigationTitle("Cheats")
    }

    private func num(_ s: String) -> Int { Int(s.trimmingCharacters(in: .whitespaces)) ?? 0 }

    private func go(_ body: String, _ args: [String: Any]) {
        Task {
            let r = await session.run("try { " + body + " } catch(e) { return 'ERROR: ' + e; }", args: args) as? String
            status = (r == "ok") ? "Done." : (r ?? "No response. Is the game loaded yet?")
        }
    }
}
