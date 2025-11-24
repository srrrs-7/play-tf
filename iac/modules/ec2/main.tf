resource "aws_instance" "this" {
  ami                  = var.ami
  instance_type        = var.instance_type
  subnet_id            = var.subnet_id
  iam_instance_profile = var.iam_instance_profile

  vpc_security_group_ids = var.vpc_security_group_ids

  user_data                   = var.user_data
  user_data_replace_on_change = var.user_data_replace_on_change

  disable_api_termination = var.disable_api_termination
  monitoring              = var.monitoring

  root_block_device {
    volume_type           = var.root_block_device.volume_type
    volume_size           = var.root_block_device.volume_size
    delete_on_termination = var.root_block_device.delete_on_termination
    encrypted             = var.root_block_device.encrypted
    kms_key_id            = var.root_block_device.kms_key_id
  }

  dynamic "ebs_block_device" {
    for_each = var.ebs_block_devices
    content {
      device_name           = ebs_block_device.value.device_name
      volume_type           = ebs_block_device.value.volume_type
      volume_size           = ebs_block_device.value.volume_size
      delete_on_termination = lookup(ebs_block_device.value, "delete_on_termination", true)
      encrypted             = lookup(ebs_block_device.value, "encrypted", true)
      kms_key_id            = lookup(ebs_block_device.value, "kms_key_id", null)
    }
  }

  metadata_options {
    http_endpoint               = var.metadata_options.http_endpoint
    http_tokens                 = var.metadata_options.http_tokens
    http_put_response_hop_limit = var.metadata_options.http_put_response_hop_limit
    instance_metadata_tags      = var.metadata_options.instance_metadata_tags
  }

  tags = merge(
    {
      "Name" = var.name
    },
    var.tags
  )

  lifecycle {
    ignore_changes = [
      ami,
      user_data,
    ]
  }
}
