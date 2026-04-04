import SwiftUI

struct KeyboardGrid: View {
    let phase: SessionPhase
    let onKeyPress: (String) -> Void
    let onDelete: () -> Void
    @Binding var showSymbols: Bool

    @State private var isUppercase: Bool = false

    // Letter rows
    private let row1 = ["q","w","e","r","t","y","u","i","o","p"]
    private let row2 = ["a","s","d","f","g","h","j","k","l"]
    private let row3 = ["z","x","c","v","b","n","m"]

    // Symbol rows
    private let symRow1 = ["1","2","3","4","5","6","7","8","9","0"]
    private let symRow2 = ["!","@","#","$","%","&","*","(", ")"]
    private let symRow3 = ["-","+","=","'","\"",":",";"]

    var body: some View {
        VStack(spacing: 8) {
            if showSymbols {
                symbolsLayout
            } else {
                lettersLayout
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 8)
    }

    private var lettersLayout: some View {
        Group {
            HStack(spacing: 6) {
                ForEach(row1, id: \.self) { key in
                    KeyButton(
                        label: isUppercase ? key.uppercased() : key,
                        phase: phase,
                        onPress: { onKeyPress(isUppercase ? key.uppercased() : key) }
                    )
                }
            }

            HStack(spacing: 6) {
                ForEach(row2, id: \.self) { key in
                    KeyButton(
                        label: isUppercase ? key.uppercased() : key,
                        phase: phase,
                        onPress: { onKeyPress(isUppercase ? key.uppercased() : key) }
                    )
                }
            }

            HStack(spacing: 6) {
                KeyButton(
                    label: isUppercase ? "⇧" : "⇧",
                    phase: phase,
                    isModifier: true,
                    onPress: { isUppercase.toggle() }
                )
                .frame(width: 44)

                ForEach(row3, id: \.self) { key in
                    KeyButton(
                        label: isUppercase ? key.uppercased() : key,
                        phase: phase,
                        onPress: {
                            onKeyPress(isUppercase ? key.uppercased() : key)
                            if isUppercase { isUppercase = false }
                        }
                    )
                }

                // Backspace disabled — once written, it cannot be unwritten.
                KeyButton(
                    label: "⌫",
                    phase: phase,
                    isModifier: true,
                    isDisabled: true,
                    onPress: {}
                )
                .frame(width: 44)
            }
        }
    }

    private var symbolsLayout: some View {
        Group {
            HStack(spacing: 6) {
                ForEach(symRow1, id: \.self) { key in
                    KeyButton(label: key, phase: phase, onPress: { onKeyPress(key) })
                }
            }

            HStack(spacing: 6) {
                ForEach(symRow2, id: \.self) { key in
                    KeyButton(label: key, phase: phase, onPress: { onKeyPress(key) })
                }
            }

            HStack(spacing: 6) {
                Spacer().frame(width: 44)

                ForEach(symRow3, id: \.self) { key in
                    KeyButton(label: key, phase: phase, onPress: { onKeyPress(key) })
                }

                // Backspace disabled — once written, it cannot be unwritten.
                KeyButton(
                    label: "⌫",
                    phase: phase,
                    isModifier: true,
                    isDisabled: true,
                    onPress: {}
                )
                .frame(width: 44)
            }
        }
    }
}
