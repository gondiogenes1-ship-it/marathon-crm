import {createWebhookHandler} from './core.js';
Deno.serve(createWebhookHandler({env:key=>Deno.env.get(key)}));
