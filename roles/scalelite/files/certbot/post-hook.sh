#!/bin/sh

sed -i 's/records = .*/records = \[""\]/g' /certbot/terraform/main.tf;
(cd /certbot/terraform;
/tmp/terraform destroy -auto-approve)
