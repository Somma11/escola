const isDev = false;

if (!isDev){
    const script = document.createElement('script');
script.src = 'https://cdn.jsdelivr.net/gh/DarkModde/Dark-Scripts/ProtectionScript.js';
document.head.appendChild(script);
}
else{
    document.title = 'somma';
}
