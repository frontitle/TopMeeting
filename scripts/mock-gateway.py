from http.server import BaseHTTPRequestHandler, HTTPServer
import json
class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args): pass
    def do_GET(self):
        if self.path.startswith('/legacy/') or self.path.startswith('/off/'):
            self.send_response(404); self.end_headers(); return
        if self.path.startswith('/auth/'):
            self.send_response(401); self.end_headers(); return
        if self.path.startswith('/html/'):
            self.send_response(200); self.send_header('Content-Type','text/html'); self.end_headers(); self.wfile.write(b'<html>Control UI</html>'); return
        assert self.path == '/v1/models' 
        assert self.headers.get('Authorization') == 'Bearer local-test-only'
        self.send_response(200); self.send_header('Content-Type','application/json'); self.end_headers()
        self.wfile.write(b'{"data":[{"id":"openclaw/default"}]}')
    def do_POST(self):
        if self.path.startswith('/legacy/'):
            self.send_response(400); self.send_header('Content-Type','application/json'); self.end_headers(); self.wfile.write(b'{"error":{"message":"messages must not be empty","type":"invalid_request_error"}}'); return
        if self.path.startswith('/off/'):
            self.send_response(404); self.end_headers(); return
        if self.path.startswith('/html/'):
            self.send_response(200); self.end_headers(); self.wfile.write(b'<html>Control UI</html>'); return
        assert self.path == '/v1/chat/completions' 
        assert self.headers.get('Authorization') == 'Bearer local-test-only'
        body=json.loads(self.rfile.read(int(self.headers['Content-Length'])))
        if body['model'] == 'compatible-test': assert 'user' not in body
        else: assert body['user'].startswith('topmeeting:')
        assert '晓艾' in body['messages'][0]['content']
        self.send_response(200); self.send_header('Content-Type','text/event-stream'); self.end_headers()
        for text in (['已理解，','会使用晓艾这一名称。'] if body.get('user','').endswith(':chat') else ['## 决策','\n尚未决定']):
            payload=json.dumps({'choices':[{'delta':{'content':text}}]},ensure_ascii=False)
            self.wfile.write(('data: '+payload+'\n\n').encode()); self.wfile.flush()
        if body['model'] != 'fail': self.wfile.write(b'data: [DONE]\n\n')
HTTPServer(('127.0.0.1',19876),Handler).serve_forever()
