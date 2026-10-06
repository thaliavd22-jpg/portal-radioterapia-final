#!/usr/bin/env ruby
# Portal de exámenes — Radioterapia / Gliomas
# Uso: ruby server.rb   →  abrir http://localhost:3000
require 'webrick'
require 'json'
require 'securerandom'
require 'cgi'

PORT = (ENV['PORT'] || 3000).to_i
DIR  = File.dirname(__FILE__)
USERS   = JSON.parse(File.read(File.join(DIR,'users.json')))
QUIZZES = JSON.parse(File.read(File.join(DIR,'quizzes.json')))
RESULTS_PATH = File.join(DIR,'results.json')
SNAPSHOTS_DIR = File.join(DIR,'snapshots')
Dir.mkdir(SNAPSHOTS_DIR) unless Dir.exist?(SNAPSHOTS_DIR)
INF_DIR = File.join(DIR,'informes'); Dir.mkdir(INF_DIR) unless Dir.exist?(INF_DIR)
INF_UP_DIR = File.join(DIR,'informes_subidos'); Dir.mkdir(INF_UP_DIR) unless Dir.exist?(INF_UP_DIR)
REPO_DIR = File.join(DIR,'repositorio'); Dir.mkdir(REPO_DIR) unless Dir.exist?(REPO_DIR)
ATT_PATH = File.join(DIR,'asistencia.json'); File.write(ATT_PATH,'[]') unless File.exist?(ATT_PATH)
GRADES_PATH = File.join(DIR,'calificaciones.json'); File.write(GRADES_PATH,'{}') unless File.exist?(GRADES_PATH)
File.write(RESULTS_PATH,'[]') unless File.exist?(RESULTS_PATH)
SESSIONS = {}   # token => {role:, email:, nombre:}

def h(s); CGI.escapeHTML(s.to_s); end

def page(title, body)
  <<~HTML
  <!DOCTYPE html><html lang="es"><head><meta charset="utf-8"><title>#{title}</title>
  <style>body{font-family:Georgia,serif;max-width:900px;margin:40px auto;padding:0 20px}
  .card{border:1px solid #ccc;border-radius:10px;padding:20px;margin:16px 0}
  input{padding:8px;width:100%;margin:6px 0;box-sizing:border-box}
  button{padding:10px 18px;background:#2c6fbb;color:#fff;border:none;border-radius:6px;cursor:pointer}
  table{border-collapse:collapse;width:100%}td,th{border:1px solid #ccc;padding:6px}</style></head>
  <body><h1>#{title}</h1>#{body}</body></html>
  HTML
end

def current_user(req)
  tok = req.cookies.find { |c| c.name == 'token' }&.value
  tok && SESSIONS[tok]
end

server = WEBrick::HTTPServer.new(Port: PORT, BindAddress: '0.0.0.0', DocumentRoot: DIR, AccessLog: [], Logger: WEBrick::Log.new(File::NULL))

server.mount_proc('/') do |req,res|
  u = current_user(req)
  if u && u['role'] == 'admin'
    res.set_redirect(WEBrick::HTTPStatus::Found, '/admin')
  elsif u
    res.set_redirect(WEBrick::HTTPStatus::Found, '/select')
  else
    res.set_redirect(WEBrick::HTTPStatus::Found, '/login')
  end
end

server.mount_proc('/login') do |req,res|
  if req.request_method == 'GET'
    res.body = page('Ingreso al portal de exámenes', <<~B)
      <div class="card"><form method="post" action="/login">
      <label>Correo institucional</label><input name="email" type="email" required>
      <label>Contraseña</label><input name="password" type="password" required>
      <button type="submit">Ingresar</button></form></div>
      <p><a href="/admin/login">Acceso docente (admin)</a></p>
    B
  else
    email = req.query['email'].to_s.strip.downcase
    pass  = req.query['password'].to_s
    alumno = USERS['alumnos'].find { |a| a['email'].downcase == email && a['password'] == pass }
    if alumno
      tok = SecureRandom.hex(16); SESSIONS[tok] = {'role'=>'alumno','email'=>email,'nombre'=>alumno['nombre']}
      res.cookies << WEBrick::Cookie.new('token', tok)
      res.set_redirect(WEBrick::HTTPStatus::Found, '/select')
    else
      res.body = page('Error', '<p>Credenciales inválidas.</p><a href="/login">Volver</a>')
    end
  end
end

server.mount_proc('/admin/login') do |req,res|
  if req.request_method == 'GET'
    res.body = page('Acceso administrador', <<~B)
      <div class="card"><form method="post" action="/admin/login">
      <label>Correo institucional</label><input name="email" type="email" required>
      <label>Contraseña</label><input name="password" type="password" required>
      <button type="submit">Ingresar</button></form></div>
    B
  else
    email = req.query['email'].to_s.strip.downcase; pass = req.query['password'].to_s
    if email == USERS['admin']['email'] && pass == USERS['admin']['password']
      tok = SecureRandom.hex(16); SESSIONS[tok] = {'role'=>'admin','email'=>email}
      res.cookies << WEBrick::Cookie.new('token', tok)
      res.set_redirect(WEBrick::HTTPStatus::Found, '/admin')
    else
      res.body = page('Error', '<p>Credenciales de administrador inválidas.</p>')
    end
  end
end

server.mount_proc('/admin') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  results = JSON.parse(File.read(RESULTS_PATH))
  att = JSON.parse(File.read(ATT_PATH))
  grades = JSON.parse(File.read(GRADES_PATH))
  subidos = Dir[File.join(INF_UP_DIR,'*')].group_by { |f| File.basename(f).split('_').first.split('@').first rescue '' }
  rows = USERS['alumnos'].map do |a|
    email_clean = a['email'].gsub(/[^a-z0-9_.-]/i,'_')
    exams = results.select { |r| r['email'] == a['email'] }.map { |r| "#{r['quiz']}: #{r['aciertos']}/#{r['total']}" }.join('<br>')
    present = att.count { |r| r['email'] == a['email'] && r['estado'] == 'Presente' }
    infs = Dir[File.join(INF_UP_DIR,'*')].count { |f| File.basename(f).start_with?(email_clean) }
    grade = grades[a['email']] || ''
    "<tr><td>#{h a['nombre']}</td><td>#{h a['email']}</td><td>#{present}</td><td>#{exams.empty? ? '-' : exams}</td><td>#{infs}</td>
    <td><form method='post' action='/admin/calificar'><input type='hidden' name='email' value='#{a['email']}'>
    <input type='text' name='nota' value='#{h grade}' size='4'><button>Guardar</button></form></td></tr>"
  end.join
  res.body = page('Control final — Asistencia, Exámenes, Informes y Calificación', <<~B)
    <h3>Resumen por alumno</h3>
    <table><tr><th>Alumno</th><th>Correo</th><th>Asistencias presentes</th><th>Exámenes</th><th>Informes</th><th>Calificación del profesor</th></tr>
    #{rows}</table>
    <h3>Accesos rápidos</h3>
    <p><a href='/admin/asistencia'>📋 Registrar / ver asistencia</a><br>
    <a href='/admin/informes'>📝 Esquemas y control de informes</a><br>
    <a href='/admin/repositorio'>📚 Subir libro al repositorio</a><br>
    <a href='/logout'>Cerrar sesión</a></p>
    <h3>Fotos de vigilancia (más recientes)</h3>
    #{Dir[File.join(SNAPSHOTS_DIR,'*.jpg')].sort_by { |f| File.mtime(f) }.last(20).reverse.map { |f| "<p><b>#{File.basename(f)}</b><br><img src='/snapshots/#{File.basename(f)}' width='240'></p>" }.join}
  B
end

server.mount_proc('/portal') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  res.set_redirect(WEBrick::HTTPStatus::Found, '/select')
end

server.mount_proc('/asistencia') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  records = JSON.parse(File.read(ATT_PATH)).select { |r| r['email'] == u['email'] }
  rows = records.map { |r| "<tr><td>#{h r['fecha']}</td><td>#{h r['hora']}</td><td>#{h r['estado']}</td></tr>" }.join
  res.body = page('Mi asistencia', "<table><tr><th>Fecha</th><th>Hora</th><th>Estado</th></tr>#{rows}</table><p><a href='/portal'>Volver</a></p>")
end

server.mount_proc('/informes') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  if req.request_method == 'POST'
    f = req.query['informe']
    if f && f.respond_to?(:read)
      name = "#{u['email'].gsub(/[^a-z0-9_.-]/i,'_')}_#{Time.now.to_i}_#{File.basename(f.filename)}"
      File.binwrite(File.join(INF_UP_DIR, name), f.read)
      res.set_redirect(WEBrick::HTTPStatus::Found, '/informes')
    end
  else
    esquemas = Dir[File.join(INF_DIR,'*')].map { |f| "<li><a href='/informe/#{File.basename(f)}'>#{File.basename(f)}</a></li>" }.join
    mis = Dir[File.join(INF_UP_DIR,'*')].select { |f| File.basename(f).start_with?(u['email'].gsub(/[^a-z0-9_.-]/i,'_')) }.map { |f| "<li>#{File.basename(f)}</li>" }.join
    res.body = page('Informes', <<~B)
      <h3>Esquemas para descargar</h3><ul>#{esquemas.empty? ? '<li>No hay esquemas aún.</li>' : esquemas}</ul>
      <h3>Sube tu informe</h3>
      <form method="post" action="/informes" enctype="multipart/form-data">
      <input type="file" name="informe" required><button type="submit">Subir</button></form>
      <h3>Mis informes subidos</h3><ul>#{mis.empty? ? '<li>Ninguno</li>' : mis}</ul>
      <p><a href='/portal'>Volver</a></p>
    B
  end
end

server.mount_proc('/repositorio') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  libros = Dir[File.join(REPO_DIR,'*')].map { |f| "<li><a href='/libro/#{File.basename(f)}'>#{File.basename(f)}</a></li>" }.join
  res.body = page('Repositorio de libros', "<ul>#{libros.empty? ? '<li>No hay materiales aún.</li>' : libros}</ul><p><a href='/portal'>Volver</a></p>")
end

server.mount_proc('/informe') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u
  name = req.path.split('/').last
  path = File.join(INF_DIR, name)
  res['Content-Type'] = 'application/octet-stream'; res['Content-Disposition'] = "attachment; filename=\"#{name}\""
  res.body = File.read(path) if File.exist?(path)
end

server.mount_proc('/libro') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u
  name = req.path.split('/').last
  path = File.join(REPO_DIR, name)
  res['Content-Type'] = 'application/octet-stream'; res['Content-Disposition'] = "inline; filename=\"#{name}\""
  res.body = File.read(path) if File.exist?(path)
end

# ---------- Admin: secciones ----------
server.mount_proc('/admin/asistencia') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  if req.request_method == 'POST'
    email = req.query['email'].to_s
    alumno = USERS['alumnos'].find { |a| a['email'] == email }
    if alumno
      att = JSON.parse(File.read(ATT_PATH))
      att << {'email'=>email,'nombre'=>alumno['nombre'],'fecha'=>req.query['fecha'],'hora'=>req.query['hora'],'estado'=>req.query['estado']}
      File.write(ATT_PATH, JSON.pretty_generate(att))
    end
    res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/asistencia')
  else
    opts = USERS['alumnos'].map { |a| "<option value='#{a['email']}'>#{a['nombre']} (#{a['email']})</option>" }.join
    att = JSON.parse(File.read(ATT_PATH))
    rows = att.map { |r| "<tr><td>#{h r['nombre']}</td><td>#{h r['fecha']}</td><td>#{h r['hora']}</td><td>#{h r['estado']}</td></tr>" }.join
    res.body = page('Registrar asistencia', <<~B)
      <form method="post">
      <select name="email">#{opts}</select>
      <input type="date" name="fecha" required>
      <input type="time" name="hora" required>
      <select name="estado"><option>Presente</option><option>Ausente</option><option>Tarde</option></select>
      <button type="submit">Guardar</button></form>
      <table><tr><th>Nombre</th><th>Fecha</th><th>Hora</th><th>Estado</th></tr>#{rows}</table>
      <p><a href='/admin'>Volver al control</a></p>
    B
  end
end

server.mount_proc('/admin/informes') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  if req.request_method == 'POST' && req.query['esquema']
    f = req.query['esquema']
    if f && f.respond_to?(:read)
      File.binwrite(File.join(INF_DIR, File.basename(f.filename)), f.read)
    end
    res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/informes')
  else
    subidos = Dir[File.join(INF_UP_DIR,'*')].map { |f| "<li><a href='/admin/descarga/#{File.basename(f)}'>#{File.basename(f)}</a></li>" }.join
    res.body = page('Gestión de informes', <<~B)
      <h3>Subir esquema/plantilla para alumnos</h3>
      <form method="post" enctype="multipart/form-data"><input type="file" name="esquema" required><button>Subir</button></form>
      <h3>Informes subidos por alumnos</h3><ul>#{subidos.empty? ? '<li>Ninguno</li>' : subidos}</ul>
      <p><a href='/admin'>Volver al control</a></p>
    B
  end
end

server.mount_proc('/admin/descarga') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  name = req.path.split('/').last
  path = File.join(INF_UP_DIR, name)
  res['Content-Type'] = 'application/octet-stream'; res['Content-Disposition'] = "attachment; filename=\"#{name}\""
  res.body = File.read(path) if File.exist?(path)
end

server.mount_proc('/admin/repositorio') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  if req.request_method == 'POST' && req.query['libro']
    f = req.query['libro']
    if f && f.respond_to?(:read)
      File.binwrite(File.join(REPO_DIR, File.basename(f.filename)), f.read)
    end
    res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/repositorio')
  else
    res.body = page('Repositorio — subir libro', <<~B)
      <form method="post" enctype="multipart/form-data"><input type="file" name="libro" required><button>Subir libro</button></form>
      <p><a href='/admin'>Volver al control</a></p>
    B
  end
end

server.mount_proc('/admin/calificar') do |req,res|
  u = current_user(req); res.set_redirect(WEBrick::HTTPStatus::Found, '/admin/login') unless u && u['role'] == 'admin'
  if req.request_method == 'POST'
    grades = JSON.parse(File.read(GRADES_PATH))
    grades[req.query['email']] = req.query['nota']
    File.write(GRADES_PATH, JSON.pretty_generate(grades))
  end
  res.set_redirect(WEBrick::HTTPStatus::Found, '/admin')
end

server.mount_proc('/select') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  links = QUIZZES.map do |k,q|
    "<div class='card'><h3>#{h q['titulo']}</h3><p>#{q['preguntas'].size} preguntas · #{q['minutos']} min</p><a href='/exam?quiz=#{k}'><button>Comenzar</button></a></div>"
  end.join
  res.body = page("Exámenes", "#{links}<p><a href='/logout'>Cerrar sesión</a></p>")
end

server.mount_proc('/exam') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  quiz = QUIZZES[req.query['quiz']]
  preguntas_html = quiz['preguntas'].each_with_index.map do |q,i|
    ops = q['ops'].each_with_index.map do |op,j|
      "<label><input type='radio' name='q#{i}' value='#{j}'> #{('a'..'d').to_a[j]}) #{h op}</label>"
    end.join
    "<div class='card'><p><b>#{i+1}. #{h q['p']}</b></p>#{ops}</div>"
  end.join
  res.body = page(quiz['titulo'], <<~B)
    <p><b>Tiempo restante:</b> <span id="timer"></span> &nbsp;|&nbsp; <b>Salidas detectadas:</b> <span id="salidas">0</span></p>
    <style>#camStatus{animation:blink 1s infinite}@keyframes blink{50%{opacity:.2}}</style>
    <p><b>Estado de vigilancia:</b> <span id="camStatus" style="color:#c00;font-weight:bold">● CÁMARA INACTIVA</span>
    &nbsp;<button type="button" id="btnCam" onclick="requestCamera()">📷 Activar cámara</button></p>
    <video id="cam" width="160" autoplay playsinline muted style="border-radius:8px"></video>
    <canvas id="snap" width="320" height="240" style="display:none"></canvas>
    <script>
      // Bloquear examen hasta activar cámara
      const btnSubmit = document.querySelector('#examForm button[type=submit]');
      if(btnSubmit) btnSubmit.disabled = true;
      let camOk = false;
      function detectaIncognito(){
        return new Promise(async (res) => {
          // Chrome: RequestFileSystem falla en modo incógnito
          const fs = window.RequestFileSystem || window.webkitRequestFileSystem;
          if (fs) {
            fs(window.TEMPORARY, 100, () => {}, () => res(true));
          }
          // Safari/iOS: localStorage falla en modo privado
          try { localStorage.setItem('__probe__','1'); localStorage.removeItem('__probe__'); }
          catch(e){ return res(true); }
          // Cuota muy baja suele indicar modo privado
          try { const est = await navigator.storage.estimate(); if(est && est.quota && est.quota < 60*1024*1024) return res(true); } catch(e){}
          res(false);
        });
      }
      detectaIncognito().then(incog => {
        if(incog){
          document.getElementById('camStatus').textContent = '● MODO INCÓGNITO NO PERMITIDO';
          document.getElementById('examForm').style.display = 'none';
          const btnCam = document.getElementById('btnCam'); if(btnCam) btnCam.disabled = true;
          alert('No se puede rendir el examen en modo incógnito/privado. Abre el enlace desde una ventana normal.');
          return;
        }
        requestCamera();
      });
      function requestCamera(){
        document.getElementById('camStatus').textContent = '● Solicitando permiso de cámara...';
        navigator.mediaDevices.getUserMedia({video:true,audio:false}).then(stream=>{
          camOk = true;
          document.getElementById('cam').srcObject = stream;
          document.getElementById('camStatus').textContent = '● GRABANDO — vigilancia activa';
          document.getElementById('examForm').style.display='';
          const b = document.querySelector('#examForm button[type=submit]'); if(b) b.disabled = false;
        }).catch(()=>{
          document.getElementById('camStatus').textContent='● CÁMARA BLOQUEADA — revisa los permisos del navegador';
          alert('El navegador bloqueó la cámara. Toca el candado/info del sitio en la barra del navegador y permite la cámara, luego presiona "Activar cámara".');
        });
      }
      setTimeout(()=>{ if(!camOk){ document.getElementById('camStatus').textContent='● CÁMARA INACTIVA — presiona "Activar cámara"'; } },4000);
      function tomarFoto(reason){
        const v = document.getElementById('cam'); const c = document.getElementById('snap');
        if(!v.srcObject) return;
        c.getContext('2d').drawImage(v,0,0,c.width,c.height);
        fetch('/api/snapshot',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({img:c.toDataURL('image/jpeg',0.7),reason})});
      }
      setInterval(()=>tomarFoto('cada5min'), 5*60*1000);
      setTimeout(()=>tomarFoto('inicio'), 3000);
    </script>
    <form id="examForm" method="post" action="/submit" style="display:none">
    <input type="hidden" name="quiz" value="#{h req.query['quiz']}">
    <input type="hidden" name="salidas" id="salidasInput" value="0">
    <input type="hidden" name="start" id="startInput" value="#{Time.now.to_i}">
    #{preguntas_html}
    <button type="submit">Enviar examen</button></form>
    <script>
      let remaining = #{quiz['minutos']}*60, salidas = 0;
      const timerEl = document.getElementById('timer');
      const salidasEl = document.getElementById('salidas');
      setInterval(()=>{ remaining--; if(remaining<=0 && document.getElementById('camStatus').textContent.indexOf('GRABANDO')>=0){document.getElementById('examForm').submit();}
        timerEl.textContent = Math.floor(remaining/60)+':'+String(remaining%60).padStart(2,'0'); },1000);
      function registrSalida(){ salidas++; salidasEl.textContent=salidas;
        document.getElementById('salidasInput').value=salidas;
        fetch('/api/leave',{method:'POST',headers:{'Content-Type':'application/json'},body:JSON.stringify({salidas})});
        alert('Salida detectada (#'+salidas+'). Queda registrada en el informe docente.');
        tomarFoto('salida'); }
      document.addEventListener('visibilitychange',()=>{ if(document.hidden) registrSalida(); });
      window.addEventListener('blur',()=>{ registrSalida(); });
    </script>
  B
end

server.mount_proc('/api/snapshot') do |req,res|
  u = current_user(req)
  res['Content-Type'] = 'application/json'
  if u && u['role'] == 'alumno' && req.request_method == 'POST'
    data = JSON.parse(req.body.to_s) rescue {}
    img = data['img'].to_s.sub(/^data:image\/\w+;base64,/,'')
    reason = data['reason'].to_s.gsub(/[^a-z0-9_]/i,'')
    if !img.empty?
      file = File.join(SNAPSHOTS_DIR, "#{u['email'].gsub(/[^a-z0-9_.-]/i,'_')}_#{Time.now.to_i}_#{reason}.jpg")
      File.binwrite(file, Base64.decode64(img))
    end
    res.body = '{"ok":true}'
  else
    res.body = '{"ok":false}'
  end
end

server.mount_proc('/api/leave') do |req,res|
  res['Content-Type'] = 'application/json'
  res.body = '{"ok":true}'
end

server.mount_proc('/submit') do |req,res|
  u = current_user(req)
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login') unless u && u['role'] == 'alumno'
  key = req.query['quiz']; quiz = QUIZZES[key]
  correct = 0
  quiz['preguntas'].each_with_index do |q,i|
    ans = req.query["q#{i}"]
    correct += 1 if ans && ans.to_i == q['correcta']
  end
  mins = ((Time.now.to_i - req.query['start'].to_i) / 60.0).round(1)
  results = JSON.parse(File.read(RESULTS_PATH))
  results << {'nombre'=>u['nombre'],'email'=>u['email'],'quiz'=>quiz['titulo'],'aciertos'=>correct,'total'=>quiz['preguntas'].size,'minutos_usados'=>mins,'salidas'=>req.query['salidas'].to_i}
  File.write(RESULTS_PATH, JSON.pretty_generate(results))
  res.body = page('Resultado', "<div class='card'><h2>Nota: #{correct}/#{quiz['preguntas'].size}</h2><p>Tiempo usado: #{mins} min · Salidas detectadas: #{req.query['salidas']}</p><a href='/select'>Volver</a></div>")
end

server.mount_proc('/logout') do |req,res|
  tok = req.cookies.find { |c| c.name == 'token' }&.value
  SESSIONS.delete(tok) if tok
  res.cookies << WEBrick::Cookie.new('token','')
  res.set_redirect(WEBrick::HTTPStatus::Found, '/login')
end

trap('INT') { server.shutdown }
puts "Portal en http://localhost:#{PORT}"
server.start
