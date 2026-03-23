import SwiftUI

struct ServiceIcon: View {
    let service: ServiceType
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: service.systemImage)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(service.category.color, in: RoundedRectangle(cornerRadius: 7))
    }
}
