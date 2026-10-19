output "id" {
  description = "The service's unique ID"
  value       = random_id.this.hex
}
