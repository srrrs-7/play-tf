# Sample Documents for Bedrock Knowledge Base

このディレクトリには、Bedrock Knowledge Base（RAG）のテスト用サンプルドキュメントが含まれています。

## ファイル一覧

| ファイル | 内容 |
|---------|------|
| `company-policy.txt` | 会社のポリシードキュメント（勤務時間、休暇、経費など） |
| `product-faq.txt` | 製品のFAQドキュメント（機能、料金、サポートなど） |

## 使用方法

### 1. S3にアップロード

```bash
cd ..
./script.sh deploy my-rag-app
./script.sh upload-dir my-rag-app-bedrock-docs-<account-id> ./sample/
```

### 2. Knowledge Base作成（AWS Console）

1. [Bedrock Console](https://console.aws.amazon.com/bedrock/home#/knowledge-bases) を開く
2. 「Create knowledge base」をクリック
3. S3バケットをデータソースとして選択

### 3. クエリ実行

```bash
# ポリシーについて質問
./script.sh kb-query kb-xxxxxxxxx "リモートワークのポリシーは？"

# 製品について質問
./script.sh kb-query kb-xxxxxxxxx "返金ポリシーについて教えてください"
```

## サンプルクエリ

### 会社ポリシー関連

- 「年次休暇は何日もらえますか？」
- 「パスワードポリシーについて教えてください」
- 「出張時の食事手当はいくらですか？」

### 製品FAQ関連

- 「無料プランの容量は？」
- 「解約方法を教えてください」
- 「どのプラットフォームで使えますか？」

## 独自ドキュメントの追加

独自のドキュメントを追加する場合：

1. テキストファイル（.txt, .md）、PDF、Word文書をサポート
2. 最大ファイルサイズ: 50MB
3. 推奨: 構造化されたセクション、見出し、Q&A形式

```bash
# 独自ドキュメントをアップロード
./script.sh upload my-bucket /path/to/your/document.pdf

# データソースを同期
./script.sh kb-sync kb-xxx ds-xxx
```
