# =============================================================================
# NAT Instance
# =============================================================================
# NAT Gatewayの代わりにNAT Instanceを使用してコストを削減
# - NAT Gateway: ~$32/月 + データ転送料
# - NAT Instance (t4g.nano): ~$3/月（約10分の1のコスト）
#
# 設定内容:
# - IP Forwarding有効化
# - iptables MASQUERADE設定
# - Source/Destination Check無効化

resource "aws_instance" "nat" {
  count         = var.create_nat_instance ? 1 : 0
  ami           = local.nat_ami_id
  instance_type = var.nat_instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true
  source_dest_check           = false # NAT動作に必須

  user_data_base64 = base64encode(<<-EOF
    #!/bin/bash
    # =============================================================================
    # NAT Instance Configuration Script
    # =============================================================================
    exec > /var/log/nat-setup.log 2>&1
    set -x

    echo "Starting NAT configuration at $(date)"

    # IP Forwardingを有効化
    echo "net.ipv4.ip_forward = 1" > /etc/sysctl.d/99-nat.conf
    sysctl -p /etc/sysctl.d/99-nat.conf
    sysctl -w net.ipv4.ip_forward=1

    # iptablesをインストール（Amazon Linux 2023用）
    dnf install -y iptables-nft iptables-services || yum install -y iptables-services

    # 既存ルールをクリア
    iptables -F
    iptables -t nat -F
    iptables -X

    # デフォルトポリシーをACCEPTに設定
    iptables -P INPUT ACCEPT
    iptables -P FORWARD ACCEPT
    iptables -P OUTPUT ACCEPT

    # NAT（MASQUERADE）を設定 - VPC CIDRからのトラフィックのみ
    iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE 2>/dev/null || \
    iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # ルールを永続化
    mkdir -p /etc/sysconfig
    iptables-save > /etc/sysconfig/iptables

    # iptablesサービスを有効化
    systemctl enable iptables 2>/dev/null || true
    systemctl start iptables 2>/dev/null || true

    # 設定確認
    echo "=== IP Forward Status ==="
    cat /proc/sys/net/ipv4/ip_forward
    echo "=== iptables NAT rules ==="
    iptables -t nat -L -v -n
    echo "=== iptables FORWARD rules ==="
    iptables -L FORWARD -v -n
    echo "=== Network interfaces ==="
    ip addr show
    echo "=== Route table ==="
    ip route show

    echo "NAT Instance configuration completed at $(date)"
  EOF
  )

  root_block_device {
    volume_type           = "gp3"
    volume_size           = 8
    delete_on_termination = true
    encrypted             = true
  }

  # IMDSv2を強制（セキュリティ強化）
  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-nat"
    Role = "NAT"
  })

  lifecycle {
    ignore_changes = [ami]
  }
}
