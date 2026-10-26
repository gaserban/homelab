import { renderToStaticMarkup } from "react-dom/server";

import { Greeting } from "./component";

const html = renderToStaticMarkup(<Greeting name="homelab" />);
const want = '<p class="greeting">hello, homelab</p>';
if (html !== want) {
  throw new Error(`rendered ${html}, want ${want}`);
}
