server {
  listen 8080;
  server_tokens off;

  location = /healthz {
    access_log off;
    return 200 "ok\n";
  }

  location = /auth {
    if ($http_authorization = "Bearer ${api_key}") {
      return 200;
    }
    return 401;
  }
}
