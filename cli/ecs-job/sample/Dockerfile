# Sample ECS Job Dockerfile
# Build: docker build -t my-job:latest .
# Run locally: docker run --rm my-job:latest

FROM python:3.11-slim

WORKDIR /app

# Install dependencies
RUN pip install --no-cache-dir boto3

# Copy application
COPY job.py .

# Set environment variables
ENV PYTHONUNBUFFERED=1

# Run the job
CMD ["python", "job.py"]
