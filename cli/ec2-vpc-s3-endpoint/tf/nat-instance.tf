# =============================================================================
# NAT Instance
# =============================================================================
# NAT Gatewayの代わりにNAT Instanceを使用（コスト: ~$3/月 vs ~$32/月）
# 必須設定: source_dest_check=false, IP Forwarding, iptables MASQUERADE

resource "aws_instance" "nat" {
  count         = var.create_nat_instance ? 1 : 0
  ami           = local.nat_ami_id
  instance_type = var.nat_instance_type
  subnet_id     = aws_subnet.public.id

  vpc_security_group_ids      = [aws_security_group.nat[0].id]
  associate_public_ip_address = true
  source_dest_check           = false # NAT動作に必須

  user_data = <<-EOF
    #!/bin/bash
    # IP Forwarding有効化
    echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
    sysctl -w net.ipv4.ip_forward=1

    # iptables設定（Amazon Linux 2023）
    dnf install -y iptables-nft
    iptables -t nat -A POSTROUTING -o ens5 -j MASQUERADE
    iptables -A FORWARD -j ACCEPT
  EOF

  tags = merge(local.common_tags, var.tags, {
    Name = "${local.name_prefix}-nat"
  })
}
