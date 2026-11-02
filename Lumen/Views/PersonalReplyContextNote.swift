import SwiftUI

struct PersonalReplyContextNote: View {
    let message: ChatMessage
    let current: PersonalContextProvenance
    var pending = false

    private var text: String {
        guard let provenance = message.personalContext, provenance.isValid else {
            return "Whether this reply used personal notes isn’t recorded. It isn’t included with new questions."
                + (pending ? " Retry saves this same reply." : "")
        }
        guard provenance.notesSHA256 != nil else { return "No personal notes used." }
        if provenance.allowsHistory(current: current) { return "Used your shared personal notes." }
        return "Used earlier personal notes. This reply isn’t included with new questions."
            + (pending ? " Retry saves this same reply." : "")
    }

    var body: some View {
        FHIRLiteralText(text: text, identifier: pending ? "pendingPersonalContext" : "savedPersonalContext-" + message.id,
                        color: Theme.secondary, style: .footnote, selectable: false)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}
