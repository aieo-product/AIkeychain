import SwiftUI

struct CategoryIcon: View {
    let category: KeyCategory
    var size: CGFloat = 28

    var body: some View {
        Image(systemName: category.systemImage)
            .font(.system(size: size * 0.5))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(category.color, in: RoundedRectangle(cornerRadius: 6))
    }
}
