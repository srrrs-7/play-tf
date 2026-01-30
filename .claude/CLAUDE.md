# Claude Code Configuration

このディレクトリには Claude Code のプロジェクト固有の設定が含まれています。

## ディレクトリ構成

```
.claude/
├── rules/           # コンテキスト固有のルール
├── agents/          # カスタムエージェント
├── commands/        # スラッシュコマンド
├── skills/          # ガイド付きワークフロー
└── CLAUDE.md        # この説明ファイル
```

## Rules (ルール)

ファイルパターンに基づいて自動適用されるコーディング規約です。

| ルール | 適用対象 | 内容 |
|--------|----------|------|
| `terraform-modules` | `iac/modules/**/*.tf` | モジュール構造、日本語コメント、変数定義パターン |
| `terraform-environments` | `iac/environments/**/*.tf` | 環境設定、命名規則 `{project}-{env}-{purpose}` |
| `cli-scripts` | `cli/**/*.sh` | スクリプト構造、color output、common.sh使用 |
| `cli-terraform` | `cli/**/tf/**/*.tf` | CLI内の独立Terraform、stack_nameパターン |
| `lambda-typescript` | `**/*.ts` | Lambda handler、AWS SDK v3、レスポンス形式 |
| `aws-security` | 全体 | S3暗号化、IAM最小権限、シークレット管理 |

## Agents (エージェント)

特定タスクに特化した自律的サブエージェントです。

| エージェント | 用途 |
|--------------|------|
| `terraform-reviewer` | Terraform コードレビュー（セキュリティ、ベストプラクティス） |
| `cli-script-generator` | プロジェクト規約に準拠したCLIスクリプト生成 |
| `lambda-generator` | TypeScript Lambda関数生成（AWS SDK v3対応） |
| `architecture-planner` | AWSアーキテクチャ設計・パターン提案 |

## Commands (コマンド)

`/command-name` で呼び出すスラッシュコマンドです。

### Terraform操作
| コマンド | 説明 |
|----------|------|
| `/tf-init <env>` | Terraform初期化 (dev, stg, prd, s3, api) |
| `/tf-plan <env>` | 変更プレビュー |
| `/tf-apply <env>` | 変更適用（確認必要） |
| `/tf-destroy <env>` | リソース削除（破壊的） |

### ビルド・作成
| コマンド | 説明 |
|----------|------|
| `/build-lambda <path>` | TypeScript Lambdaビルド |
| `/new-module <name>` | 新規Terraformモジュール作成 |
| `/new-cli <name>` | 新規CLIスクリプト作成 |

### デプロイ・運用
| コマンド | 説明 |
|----------|------|
| `/deploy <arch> <name>` | アーキテクチャデプロイ |
| `/destroy <arch> <name>` | アーキテクチャ削除 |
| `/status [arch]` | デプロイ状態確認 |

### ユーティリティ
| コマンド | 説明 |
|----------|------|
| `/aws-auth` | AWS認証状態確認・設定ガイド |
| `/list-arch [category]` | 利用可能アーキテクチャ一覧 |

## Skills (スキル)

複数ステップのガイド付きワークフローです。

| スキル | 用途 | 使用例 |
|--------|------|--------|
| `terraform-workflow` | Terraform完全ワークフロー | `/terraform-workflow dev` |
| `lambda-scaffold` | Lambda関数スキャフォールディング | `/lambda-scaffold my-func api` |
| `architecture-deploy` | アーキテクチャ選択〜デプロイ | `/architecture-deploy` |
| `module-create` | Terraformモジュール作成ガイド | `/module-create cognito` |
| `cli-scaffold` | CLIスクリプトスキャフォールディング | `/cli-scaffold ses` |
| `security-audit` | セキュリティ監査 | `/security-audit iac/` |
| `infra-status` | AWSインフラ状態確認 | `/infra-status compute` |

## 使い方の例

### 新しいAPIを作成する場合

```bash
# 1. アーキテクチャを選択してデプロイ
/architecture-deploy apigw-lambda-dynamodb my-api

# または Terraform で
/terraform-workflow api
```

### 新しいLambda関数を追加する場合

```bash
# 1. スキャフォールディング
/lambda-scaffold image-processor dev

# 2. ビルド
/build-lambda iac/environments/dev/image-processor

# 3. デプロイ
/tf-apply dev
```

### セキュリティチェック

```bash
# Terraformコードの監査
/security-audit iac/

# 現在のインフラ状態確認
/infra-status
```

## カスタマイズ

### 新しいルールを追加

`.claude/rules/` に Markdown ファイルを作成:

```markdown
# My Rule

Applies to: `path/pattern/**/*.ext`

## Guidelines
...
```

### 新しいコマンドを追加

`.claude/commands/` に Markdown ファイルを作成:

```markdown
---
name: my-command
description: What this command does
user-invocable: true
---

Instructions for Claude when this command is invoked.
```

### 新しいスキルを追加

`.claude/skills/{skill-name}/SKILL.md` を作成:

```markdown
---
name: my-skill
description: Guided workflow for X
user-invocable: true
---

# My Skill

Step-by-step instructions...
```

## 注意事項

- `settings.local.json` は個人設定のため gitignore されています
- Rules は該当ファイル編集時に自動適用されます
- Skills は Commands より複雑なワークフローに適しています
- Agents は自律的に動作するため、明確なタスク定義が重要です
