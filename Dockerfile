FROM python:3.12-slim AS builder

WORKDIR /app

RUN apt-get update && apt-get install -y postgresql-client \
    && rm -rf /var/lib/apt/lists/*


COPY requirements.txt /app/requirements.txt
RUN pip install --user --no-cache-dir --default-timeout=300 --retries=10 -r /app/requirements.txt



FROM python:3.12-slim

WORKDIR /app

RUN apt-get update && apt-get install -y postgresql-client \
    && rm -rf /var/lib/apt/lists/*

COPY --from=builder /root/.local /root/.local
COPY . /app

ENV PATH=/root/.local/bin:$PATH
ENV PYTHONUNBUFFERED=1

CMD ["python", "main.py"]
