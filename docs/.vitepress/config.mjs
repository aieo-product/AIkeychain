import { defineConfig } from 'vitepress'

export default defineConfig({
  title: "AI KeyChain",
  description: "AI開発者のための macOS ネイティブ鍵管理アプリ - 設計書",
  lang: 'ja-JP',
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
            { text: 'ロードマップ', link: '/dev/roadmap' },
          ]
        }
      ],
      '/guide/': [
        {
          text: 'ユーザーガイド',
          items: [
            { text: 'はじめに', link: '/guide/' },
          ]
        }
      ],
      '/test/': [
        {
          text: '試験結果',
          items: [
            { text: '概要', link: '/test/' },
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
