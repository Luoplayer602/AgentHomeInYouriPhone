const fs=require('fs'),vm=require('vm'),assert=require('assert');
class Element {
 constructor(tag){this.tag=tag;this.children=[];this.style={};this.value='';this.disabled=false;this.classList={add(){},remove(){},contains(){return false}};this.scrollHeight=0;this.scrollTop=0;this.clientHeight=100;}
 append(...values){this.children.push(...values)} replaceChildren(...values){this.children=values} remove(){} select(){}
 set textContent(value){this.text=value} get textContent(){return this.text||''}
 set innerHTML(value){throw Error('Unsafe HTML insertion')}
}
const ids={},document={createElement:tag=>new Element(tag),createTextNode:text=>({tag:'#text',text}),getElementById:id=>ids[id]||(ids[id]=new Element(id)),body:new Element('body')};
let copied='';const context={document,console,window:{isSecureContext:true},navigator:{clipboard:{writeText:async text=>copied=text}},fetch:async()=>({ok:false,status:401,json:async()=>({error:'login required'})}),setInterval(){},clearInterval(){},setTimeout(){},EventSource:class{},crypto:require('crypto').webcrypto};
vm.createContext(context);const html=fs.readFileSync('layout/usr/share/agenthome/index.html','utf8'),script=html.match(/<script>([\s\S]*?)<\/script>/)[1];
vm.runInContext(script,context);
const holder=new Element('div');context.holder=holder;
vm.runInContext('rich(holder,"# Hello\\n```\\nprint(1)\\n```\\n| A | B |\\n| --- | ---: |\\n| x | y |\\n<script>alert(1)</script>")',context);
const code=holder.children.find(e=>e.className==='code'); assert(code); assert(code.children[0].children[0].textContent==='Code');
const table=holder.children.find(e=>e.className==='table'); assert(table&&table.children[0].children.length===2);
const button=code.children[0].children[1];button.onclick();assert(copied==='print(1)\n');
vm.runInContext('settings={interactive:false};selected="one";snapshot={state:"running"};controls()',context);assert(ids.send.disabled&&ids.stop.disabled&&ids.text.disabled&&ids.create.disabled);
vm.runInContext('settings={interactive:true};snapshot={state:"completed"};controls()',context);assert(!ids.send.disabled&&ids.stop.disabled);
console.log('PASS web UI: actual JavaScript syntax, code box, optional language, exact copy, table, literal HTML, read-only controls');
