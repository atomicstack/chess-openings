import SwiftUI

struct ProgressBarView: View {
    let current: Int
    let total: Int
    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 3).fill(.gray.opacity(0.25))
                RoundedRectangle(cornerRadius: 3).fill(.blue)
                    .frame(width: geo.size.width * (total == 0 ? 0 : CGFloat(current) / CGFloat(total)))
            }
        }.frame(height: 6)
    }
}
