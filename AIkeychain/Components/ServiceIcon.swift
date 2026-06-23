import SwiftUI

struct ServiceIcon: View {
    let service: ServiceType
    /// 表示記号の上書き（キー個別アイコン等）。未指定はサービス既定。
    var symbol: String? = nil
    var size: CGFloat = 32

    var body: some View {
        Image(systemName: symbol ?? service.systemImage)
            .font(.system(size: size * 0.45))
            .foregroundStyle(.white)
            .frame(width: size, height: size)
            .background(service.category.color, in: RoundedRectangle(cornerRadius: 7))
    }
}
