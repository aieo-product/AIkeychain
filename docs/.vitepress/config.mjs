import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "AI KeyChain",
  description: "AI開発者のための macOS ネイティブ鍵管理アプリ - 設計書",
  lang: 'ja-JP',
  base: '/AIkeychain/',
  vite: {
    build: {
      // esbuild 0.28 は vitepress 1.6 デフォルトのブラウザターゲット群への
      // destructuring 変換を未サポート（"not supported yet" でビルド失敗）
      target: 'es2020',
    },
  },
  themeConfig: {
    nav: [
      { text: 'ホーム', link: '/' },
      { text: '設計書', link: '/design/' },
      { text: '開発ガイド', link: '/dev/' },
      { text: '試験結果', link: '/test/' },
    ],
    sidebar: {
      '/design/': [
        {
          text: '設計書',
          items: [
            { text: '概要', link: '/design/' },
            { text: 'アーキテクチャ', link: '/design/architecture' },
            { text: 'データモデル', link: '/design/data-model' },
            { text: 'UI/UXデザイン', link: '/design/ui-ux' },
            { text: 'セキュリティ', link: '/design/security' },
          ]
        }
      ],
      '/dev/': [
        {
          text: '開発ガイド',
          items: [
            { text: 'セットアップ', link: '/dev/' },
            { text: 'パッケージング', link: '/dev/packaging' },
            { text: 'リリース履歴', link: '/dev/roadmap' },
          ]
        }
      ],
      '/guide/': [
        {
          text: 'ユーザーガイド',
          items: [
            { text: 'はじめに', link: '/guide/' },
            { text: 'CLI & MCP サーバー', link: '/guide/cli-mcp' },
          ]
        }
      ],
      '/test/': [
        {
          text: '試験結果',
          items: [
            { text: '概要', link: '/test/' },
            { text: 'v1.6.0 最終リリース確認', link: '/test/v1.6.0-final' },
            { text: 'v1.6.0', link: '/test/v1.6.0' },
            { text: 'v1.5.1', link: '/test/v1.5.1' },
            { text: 'v1.0.0', link: '/test/v1.0.0' },
          ]
        }
      ],
    },
    socialLinks: [
      { icon: 'github', link: 'https://github.com/aieo-product/AIkeychain' }
    ],
    footer: {
      message: 'AI開発チームのための鍵管理ツール',
      copyright: 'Copyright 2025 aieo-product'
    },
    search: {
      provider: 'local'
    }
  }
})
