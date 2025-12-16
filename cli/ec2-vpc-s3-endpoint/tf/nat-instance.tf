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

    # IP Forwardingを有効化
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1

    # iptablesでNAT（MASQUERADE）を設定
    /sbin/iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE

    # FORWARDチェーンをフラッシュしてACCEPTポリシーを設定
    /sbin/iptables -F FORWARD
    /sbin/iptables -P FORWARD ACCEPT

    # VPCからのフォワーディングを明示的に許可
    /sbin/iptables -A FORWARD -i eth0 -o eth0 -m state --state RELATED,ESTABLISHED -j ACCEPT
    /sbin/iptables -A FORWARD -i eth0 -o eth0 -j ACCEPT

    # iptablesルールを永続化
    mkdir -p /etc/sysconfig
    iptables-save > /etc/sysconfig/iptables

    # systemdサービスを作成してブート時にiptablesを復元
    cat > /etc/systemd/system/iptables-restore.service << 'SVCEOF'
    [Unit]
    Description=Restore iptables rules
    After=network.target

    [Service]
    Type=oneshot
    ExecStart=/usr/sbin/iptables-restore /etc/sysconfig/iptables

    [Install]
    WantedBy=multi-user.target
    SVCEOF

    systemctl enable iptables-restore.service

    # ログ出力
    echo "NAT Instance configuration completed at $(date)" >> /var/log/nat-setup.log
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
