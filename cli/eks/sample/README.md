# Sample Kubernetes Manifests

EKSクラスターにデプロイするサンプルマニフェストです。

## ファイル一覧

| ファイル | 内容 |
|---------|------|
| `nginx-deployment.yaml` | Nginx Webサーバーのデプロイメント、サービス、HPA |

## 使用方法

### CLIスクリプトを使用

```bash
# デプロイ
cd ..
./script.sh sample-deploy my-cluster

# 削除
./script.sh sample-delete my-cluster
```

### kubectlを直接使用

```bash
# デプロイ
kubectl apply -f nginx-deployment.yaml

# 確認
kubectl get all -n sample-app

# 削除
kubectl delete -f nginx-deployment.yaml
```

## コンポーネント

### Namespace
`sample-app` namespaceを作成してリソースを分離

### ConfigMap
カスタムHTMLページを格納

### Deployment
- 2レプリカのNginxポッド
- リソース制限: 100m-200m CPU, 128Mi-256Mi メモリ
- ヘルスチェック（liveness/readiness probe）
- ConfigMapをボリュームマウント

### Service (LoadBalancer)
- AWS Classic Load Balancerを作成
- ポート80でHTTPトラフィックを受信

### HorizontalPodAutoscaler
- CPU使用率70%でオートスケール
- 最小2、最大10ポッド

## アクセス方法

```bash
# LoadBalancer URLを取得
kubectl get svc nginx-service -n sample-app -o jsonpath='{.status.loadBalancer.ingress[0].hostname}'

# ブラウザでアクセス
# http://<LoadBalancer-URL>
```

## カスタマイズ

### レプリカ数を変更

```bash
kubectl scale deployment nginx-deployment -n sample-app --replicas=3
```

### NLBを使用する場合

`nginx-deployment.yaml`のServiceアノテーションを変更:

```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-type: "nlb"
```

### 内部ロードバランサーを使用する場合

```yaml
annotations:
  service.beta.kubernetes.io/aws-load-balancer-internal: "true"
```
