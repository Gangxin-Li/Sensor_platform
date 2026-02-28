FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY models.py main.py otel_utils.py ./

CMD ["python", "-u", "main.py"]
