import {createOnboardingHandler} from './core.js';
Deno.serve(createOnboardingHandler({env:key=>Deno.env.get(key)}));
