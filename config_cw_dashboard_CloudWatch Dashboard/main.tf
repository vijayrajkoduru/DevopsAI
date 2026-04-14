locals {
  dashboard_name_sanitized         = replace(var.dashboard_name, " ", "-")
  ecs_cluster_name_sanitized       = replace(var.ecs_cluster_name, " ", "-")
  ecs_fargate_service_name_sanitized = replace(var.ecs_fargate_service_name, " ", "-")
}

resource "aws_cloudwatch_dashboard" "cw_dashboard" {
  dashboard_name = local.dashboard_name_sanitized

  dashboard_body = jsonencode({
    widgets = [

      # ──────────────────────────────────────────────
      # Section Header – Frontend Service (ECS Cluster)
      # ──────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 0
        width  = 24
        height = 1
        properties = {
          markdown = "## Frontend Service – ECS Cluster Metrics"
        }
      },

      # ECS Cluster – CPU Utilization
      {
        type   = "metric"
        x      = 0
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – CPU Utilization"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label = "CPU Utilization"
                color = "#2ca02c"
                stat  = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 100
              label = "Percent"
            }
          }
        }
      },

      # ECS Cluster – Memory Utilization
      {
        type   = "metric"
        x      = 8
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – Memory Utilization"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS",
              "MemoryUtilization",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label  = "Memory Utilization"
                color  = "#1f77b4"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 100
              label = "Percent"
            }
          }
        }
      },

      # ECS Cluster – Running Task Count
      {
        type   = "metric"
        x      = 16
        y      = 1
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – Running Task Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "RunningTaskCount",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label  = "Running Tasks"
                color  = "#ff7f0e"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Cluster – Pending Task Count
      {
        type   = "metric"
        x      = 0
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – Pending Task Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "PendingTaskCount",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label  = "Pending Tasks"
                color  = "#d62728"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Cluster – Service Count
      {
        type   = "metric"
        x      = 8
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – Service Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "ServiceCount",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label  = "Services"
                color  = "#9467bd"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Cluster – Container Instance Count
      {
        type   = "metric"
        x      = 16
        y      = 7
        width  = 8
        height = 6
        properties = {
          title  = "Frontend Service – Container Instance Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "ContainerInstanceCount",
              "ClusterName",
              var.ecs_cluster_name,
              {
                label  = "Container Instances"
                color  = "#8c564b"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ──────────────────────────────────────────────
      # Section Header – Catalogue Service (ECS Fargate)
      # ──────────────────────────────────────────────
      {
        type   = "text"
        x      = 0
        y      = 13
        width  = 24
        height = 1
        properties = {
          markdown = "## Catalogue Service – ECS Fargate Metrics"
        }
      },

      # ECS Fargate – CPU Utilization
      {
        type   = "metric"
        x      = 0
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – CPU Utilization"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS",
              "CPUUtilization",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "CPU Utilization"
                color  = "#2ca02c"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 100
              label = "Percent"
            }
          }
        }
      },

      # ECS Fargate – Memory Utilization
      {
        type   = "metric"
        x      = 8
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – Memory Utilization"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "AWS/ECS",
              "MemoryUtilization",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Memory Utilization"
                color  = "#1f77b4"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              max   = 100
              label = "Percent"
            }
          }
        }
      },

      # ECS Fargate – Running Task Count
      {
        type   = "metric"
        x      = 16
        y      = 14
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – Running Task Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "RunningTaskCount",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Running Tasks"
                color  = "#ff7f0e"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Fargate – Desired Task Count
      {
        type   = "metric"
        x      = 0
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – Desired Task Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "DesiredTaskCount",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Desired Tasks"
                color  = "#17becf"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Fargate – Pending Task Count
      {
        type   = "metric"
        x      = 8
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – Pending Task Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "PendingTaskCount",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Pending Tasks"
                color  = "#d62728"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Fargate – Task Set Count
      {
        type   = "metric"
        x      = 16
        y      = 20
        width  = 8
        height = 6
        properties = {
          title  = "Catalogue Service – Task Set Count"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "TaskSetCount",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Task Sets"
                color  = "#bcbd22"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Count"
            }
          }
        }
      },

      # ECS Fargate – Ephemeral Storage Reserved
      {
        type   = "metric"
        x      = 0
        y      = 26
        width  = 12
        height = 6
        properties = {
          title  = "Catalogue Service – Ephemeral Storage Reserved"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "EphemeralStorageReserved",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Storage Reserved (GB)"
                color  = "#e377c2"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Gigabytes"
            }
          }
        }
      },

      # ECS Fargate – Ephemeral Storage Utilized
      {
        type   = "metric"
        x      = 12
        y      = 26
        width  = 12
        height = 6
        properties = {
          title  = "Catalogue Service – Ephemeral Storage Utilized"
          view   = "timeSeries"
          stacked = false
          region = var.aws_region
          metrics = [
            [
              "ECS/ContainerInsights",
              "EphemeralStorageUtilized",
              "ServiceName",
              var.ecs_fargate_service_name,
              {
                label  = "Storage Utilized (GB)"
                color  = "#7f7f7f"
                stat   = "Average"
                period = 60
              }
            ]
          ]
          yAxis = {
            left = {
              min   = 0
              label = "Gigabytes"
            }
          }
        }
      }
    ]
  })
}