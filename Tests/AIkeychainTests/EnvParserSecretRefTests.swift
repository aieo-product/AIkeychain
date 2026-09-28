import Foundation
import Testing
@testable import AIkeychain

/// Secret Reference の `keychain://` 参照行とアプリ管理の `AIKEYCHAIN_` 変数を
/// .env インポート候補にしない（#219）。候補化すると既存の実シークレットが
/// 参照文字列で上書きされ、.zshrc の参照行も削除されて Secret Reference 設定が壊れる。
@Suite("EnvParser Secret Reference exclusion (#219)")
struct EnvParserSecretRefTests {

    @Test("keychain:// reference line is not offered (#219)")
    func referenceLineExcluded() {
        #expect(EnvParser.parse("export OPENAI_API_KEY=\"keychain://OPENAI_API_KEY\"\n").isEmpty)
        #expect(EnvParser.parse("export OPENAI_API_KEY='keychain://OPENAI_API_KEY'\n").isEmpty)
        #expect(EnvParser.parse("OPENAI_API_KEY=keychain://OPENAI_API_KEY\n").isEmpty)
        #expect(EnvParser.parse("OPENAI_API_KEY=KeyChain://OPENAI_API_KEY\n").isEmpty) // スキームは大小無視
    }

    @Test("a reference as the last assignment drops the key; a real value after a reference wins (#219)")
    func lastAssignmentRule() {
        #expect(EnvParser.parse("K=sk-real\nK=keychain://K\n").isEmpty)

        let realLast = EnvParser.parse("K=keychain://K\nK=sk-real\n")
        #expect(realLast.map(\.key) == ["K"])
        #expect(realLast.first?.value == "sk-real")
    }

    @Test("AIKEYCHAIN_ app-managed variables are not offered (#219)")
    func appManagedVarsExcluded() {
        #expect(EnvParser.parse("AIKEYCHAIN_SESSION_TOKEN=abc\n").isEmpty)
        #expect(EnvParser.parse("export AIKEYCHAIN_SESSION_TOKEN=abc\nK=v\n").map(\.key) == ["K"])
    }

    @Test("values merely containing keychain:// or the word keychain are still imported (#219)")
    func containsOnlyIsKept() {
        let notes = EnvParser.parse("NOTE=my keychain://notes path\nMY_KEYCHAIN_TOKEN=sk-abc\n")
        #expect(notes.map(\.key) == ["NOTE", "MY_KEYCHAIN_TOKEN"])
        #expect(notes.first?.value == "my keychain://notes path")
    }

    @Test("a realistic Secret Reference .zshrc snippet yields no candidates (#219)")
    func realisticSecretReferenceSnippet() {
        let snippet = """
        # >>> AI KeyChain >>>
        if [ -f ~/.aikeychain_proxy ]; then
          _aikp=$(grep -om1 'localhost:[0-9]*' ~/.aikeychain_proxy | head -1 | cut -d: -f2)
          if [ -n "$_aikp" ] && /usr/bin/nc -z -G 1 127.0.0.1 "$_aikp" >/dev/null 2>&1; then
            source ~/.aikeychain_proxy
          else
            rm -f ~/.aikeychain_proxy
          fi
          unset _aikp
        fi
        # <<< AI KeyChain <<<
        # AI KeyChain - Secret Reference exports
        # Keys are resolved at runtime via 'akc run'
        # --- AI ---
        # [AI KeyChain] OpenAI
        export OPENAI_API_KEY="keychain://OPENAI_API_KEY"
        # [AI KeyChain] Anthropic
        export ANTHROPIC_API_KEY="keychain://ANTHROPIC_API_KEY"
        # --- Code & Git ---
        # [AI KeyChain] GitHub
        export GITHUB_TOKEN="keychain://GITHUB_TOKEN"
        export AIKEYCHAIN_SESSION_TOKEN=0123456789abcdef
        """
        #expect(EnvParser.parse(snippet).isEmpty)
    }
}
