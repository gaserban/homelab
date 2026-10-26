variable "name" {
  type        = string
  description = "Who to greet."
}

output "greeting" {
  value       = "hello, ${var.name}"
  description = "The greeting."
}
