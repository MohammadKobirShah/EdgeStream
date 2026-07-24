FROM debian:12-slim

RUN apt-get update && apt-get install -y --no-install-recommends \
    nginx python3 python3-pip python3-venv supervisor gettext-base ca-certificates \
    && rm -rf /var/lib/apt/lists/*

RUN python3 -m venv /opt/venv
ENV PATH="/opt/venv/bin:$PATH" PYTHONPATH=/app PYTHONUNBUFFERED=1

COPY app/requirements.txt /app/requirements.txt
RUN pip install --no-cache-dir -r /app/requirements.txt
COPY app/ /app/
COPY nginx.conf.template /etc/nginx/nginx.conf.template
COPY supervisord.conf /etc/supervisor/conf.d/supervisord.conf
COPY entrypoint.sh /entrypoint.sh
RUN chmod +x /entrypoint.sh && mkdir -p /var/log/nginx /etc/nginx/conf.d

EXPOSE 8080
ENTRYPOINT ["/entrypoint.sh"]
