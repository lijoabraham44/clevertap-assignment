output "vpc_id" {
  value = module.vpc.vpc_id
}

output "private_subnet_ids" {
  value = module.vpc.private_subnet_ids
}

output "eks_cluster_name" {
  value = module.eks.cluster_name
}

output "eks_cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "transit_gateway_id" {
  value = module.tgw.transit_gateway_id
}

output "transit_gateway_arn" {
  value = module.tgw.transit_gateway_arn
}
