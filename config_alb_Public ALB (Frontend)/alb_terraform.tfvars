environment             = "dev"
route53_zone_name       = "dev.daws84s.site"
frontend_subdomain      = "app"
frontend_container_port = 3000
health_check_path       = "/"
ecs_cluster_name        = "Frontend Service"

# Populate these with your actual infrastructure values
# vpc_id            = "vpc-xxxxxxxxxxxxxxxxx"
# public_subnet_ids = ["subnet-xxxxxxxxxxxxxxxxx", "subnet-xxxxxxxxxxxxxxxxx"]