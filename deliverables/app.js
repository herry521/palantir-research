const embeddedParams = new URLSearchParams(window.location.search);
if (embeddedParams.get("embed") === "1") {
  document.documentElement.classList.add("is-embedded-root");
}

function isInPagesDirectory() {
  return window.location.pathname.split("/").slice(0, -1).includes("pages");
}

function previewPageHref(docPath) {
  const previewPage = isInPagesDirectory() ? "md-preview.html" : "pages/md-preview.html";
  return `${previewPage}?doc=${encodeURIComponent(docPath)}`;
}

function markdownPathFromHref(href) {
  if (!href || href.startsWith("#") || href.startsWith("http://") || href.startsWith("https://") || href.startsWith("mailto:")) {
    return null;
  }

  const url = new URL(href, window.location.href);
  const pathParts = decodeURIComponent(url.pathname).split("/").filter(Boolean);
  const docsIndex = pathParts.lastIndexOf("docs");
  if (docsIndex === -1) {
    return null;
  }

  const docPath = pathParts.slice(docsIndex).join("/");
  return docPath.endsWith(".md") ? docPath : null;
}

function rewriteMarkdownLinks() {
  document.querySelectorAll('a[href$=".md"]').forEach((link) => {
    if (link.dataset.noMdPreview === "1") {
      return;
    }

    const docPath = markdownPathFromHref(link.getAttribute("href"));
    if (!docPath) {
      return;
    }

    link.setAttribute("href", previewPageHref(docPath));
    link.dataset.mdPreviewLink = "1";
  });
}

function escapeHtml(value) {
  return String(value)
    .replaceAll("&", "&amp;")
    .replaceAll("<", "&lt;")
    .replaceAll(">", "&gt;")
    .replaceAll('"', "&quot;")
    .replaceAll("'", "&#39;");
}

function resolveMarkdownTarget(currentDocPath, target) {
  const [pathOnly, hash = ""] = target.split("#", 2);
  if (!pathOnly || pathOnly.startsWith("http://") || pathOnly.startsWith("https://") || pathOnly.startsWith("mailto:")) {
    return target;
  }

  const currentDir = currentDocPath.split("/").slice(0, -1);
  const segments = pathOnly.split("/");
  const resolved = [...currentDir];
  segments.forEach((segment) => {
    if (!segment || segment === ".") return;
    if (segment === "..") {
      resolved.pop();
    } else {
      resolved.push(segment);
    }
  });

  const docPath = resolved.join("/");
  if (!docPath.endsWith(".md")) {
    return target;
  }

  const suffix = hash ? `#${hash}` : "";
  return `md-preview.html?doc=${encodeURIComponent(docPath)}${suffix}`;
}

function renderInlineMarkdown(value, currentDocPath) {
  const codeTokens = [];
  let text = String(value).replace(/`([^`]+)`/g, (_, code) => {
    const token = `@@CODE${codeTokens.length}@@`;
    codeTokens.push(`<code>${escapeHtml(code)}</code>`);
    return token;
  });

  text = escapeHtml(text);
  text = text.replace(/\[([^\]]+)\]\(([^)]+)\)/g, (_, label, target) => {
    const cleanTarget = target.replace(/^&lt;|&gt;$/g, "");
    const href = resolveMarkdownTarget(currentDocPath, cleanTarget);
    return `<a href="${escapeHtml(href)}">${label}</a>`;
  });
  text = text.replace(/\*\*([^*]+)\*\*/g, "<strong>$1</strong>");
  text = text.replace(/\*([^*]+)\*/g, "<em>$1</em>");

  codeTokens.forEach((html, index) => {
    text = text.replace(`@@CODE${index}@@`, html);
  });

  return text;
}

function isTableSeparator(line) {
  return /^\s*\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?\s*$/.test(line);
}

function splitTableRow(line) {
  return line
    .trim()
    .replace(/^\|/, "")
    .replace(/\|$/, "")
    .split("|")
    .map((cell) => cell.trim());
}

function renderMarkdown(markdown, currentDocPath) {
  const lines = String(markdown || "").replace(/\r\n/g, "\n").split("\n");
  const html = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];

    if (!line.trim()) {
      index += 1;
      continue;
    }

    const codeFence = line.match(/^```(\w+)?\s*$/);
    if (codeFence) {
      const lang = codeFence[1] || "";
      const codeLines = [];
      index += 1;
      while (index < lines.length && !/^```\s*$/.test(lines[index])) {
        codeLines.push(lines[index]);
        index += 1;
      }
      index += 1;
      html.push(`<pre><code class="language-${escapeHtml(lang)}">${escapeHtml(codeLines.join("\n"))}</code></pre>`);
      continue;
    }

    if (/^\s*\|/.test(line) && index + 1 < lines.length && isTableSeparator(lines[index + 1])) {
      const headerCells = splitTableRow(line);
      index += 2;
      const rows = [];
      while (index < lines.length && /^\s*\|/.test(lines[index])) {
        rows.push(splitTableRow(lines[index]));
        index += 1;
      }
      html.push(
        `<table><thead><tr>${headerCells.map((cell) => `<th>${renderInlineMarkdown(cell, currentDocPath)}</th>`).join("")}</tr></thead><tbody>${rows
          .map((row) => `<tr>${row.map((cell) => `<td>${renderInlineMarkdown(cell, currentDocPath)}</td>`).join("")}</tr>`)
          .join("")}</tbody></table>`
      );
      continue;
    }

    const heading = line.match(/^(#{1,6})\s+(.+)$/);
    if (heading) {
      const level = heading[1].length;
      html.push(`<h${level}>${renderInlineMarkdown(heading[2], currentDocPath)}</h${level}>`);
      index += 1;
      continue;
    }

    if (/^\s*[-*]\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*[-*]\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*[-*]\s+/, ""));
        index += 1;
      }
      html.push(`<ul>${items.map((item) => `<li>${renderInlineMarkdown(item, currentDocPath)}</li>`).join("")}</ul>`);
      continue;
    }

    if (/^\s*\d+\.\s+/.test(line)) {
      const items = [];
      while (index < lines.length && /^\s*\d+\.\s+/.test(lines[index])) {
        items.push(lines[index].replace(/^\s*\d+\.\s+/, ""));
        index += 1;
      }
      html.push(`<ol>${items.map((item) => `<li>${renderInlineMarkdown(item, currentDocPath)}</li>`).join("")}</ol>`);
      continue;
    }

    if (/^\s*>/.test(line)) {
      const quoteLines = [];
      while (index < lines.length && /^\s*>/.test(lines[index])) {
        quoteLines.push(lines[index].replace(/^\s*>\s?/, ""));
        index += 1;
      }
      html.push(`<blockquote>${renderInlineMarkdown(quoteLines.join(" "), currentDocPath)}</blockquote>`);
      continue;
    }

    if (/^\s*---+\s*$/.test(line)) {
      html.push("<hr />");
      index += 1;
      continue;
    }

    const paragraphLines = [];
    while (
      index < lines.length &&
      lines[index].trim() &&
      !/^(#{1,6})\s+/.test(lines[index]) &&
      !/^```/.test(lines[index]) &&
      !/^\s*[-*]\s+/.test(lines[index]) &&
      !/^\s*\d+\.\s+/.test(lines[index]) &&
      !/^\s*>/.test(lines[index])
    ) {
      paragraphLines.push(lines[index]);
      index += 1;
    }
    html.push(`<p>${renderInlineMarkdown(paragraphLines.join(" "), currentDocPath)}</p>`);
  }

  return html.join("\n");
}

function renderMarkdownDocumentList(documents, activePath) {
  return documents
    .map((doc) => {
      const activeClass = doc.path === activePath ? " active" : "";
      return `<a class="md-doc-link${activeClass}" href="md-preview.html?doc=${encodeURIComponent(doc.path)}"><strong>${escapeHtml(doc.title)}</strong><span>${escapeHtml(doc.path)}</span></a>`;
    })
    .join("");
}

function renderMarkdownPreview() {
  const target = document.querySelector("[data-md-preview-doc]");
  if (!target || !window.PALANTIR_MD_DOCS) {
    return;
  }

  const params = new URLSearchParams(window.location.search);
  const activePath = params.get("doc") || "docs/library/README.md";
  const docsByPath = window.PALANTIR_MD_DOCS.documents || {};
  const documents = Object.values(docsByPath).sort((left, right) => left.path.localeCompare(right.path));
  const doc = docsByPath[activePath];

  const titleNode = document.querySelector("[data-md-title]");
  const pathNode = document.querySelector("[data-md-path]");
  const rawLink = document.querySelector("[data-md-raw-link]");
  const listNode = document.querySelector("[data-md-doc-list]");
  const searchNode = document.querySelector("[data-md-search]");

  if (listNode) {
    listNode.innerHTML = renderMarkdownDocumentList(documents, activePath);
  }

  if (searchNode && listNode) {
    searchNode.addEventListener("input", () => {
      const query = searchNode.value.trim().toLowerCase();
      const filtered = documents.filter((item) => `${item.title} ${item.path}`.toLowerCase().includes(query));
      listNode.innerHTML = renderMarkdownDocumentList(filtered, activePath);
    });
  }

  if (!doc) {
    if (titleNode) titleNode.textContent = "未找到文档";
    if (pathNode) pathNode.textContent = activePath;
    target.innerHTML = `<div class="md-empty-state"><h2>没有找到这个 Markdown 文档</h2><p>当前 bundle 中不存在 <code>${escapeHtml(activePath)}</code>。请从左侧文档列表重新选择。</p></div>`;
    return;
  }

  document.title = `${doc.title} - Markdown 文档预览`;
  if (titleNode) titleNode.textContent = doc.title;
  if (pathNode) pathNode.textContent = doc.path;
  if (rawLink) {
    rawLink.href = `https://gitlabee.chehejia.com/huyongqiang/palantir-research/-/blob/main/${doc.path}`;
    rawLink.target = "_blank";
    rawLink.rel = "noopener noreferrer";
    rawLink.textContent = "在 GitLab EE 打开原始 Markdown";
  }
  target.innerHTML = renderMarkdown(doc.content, doc.path);
}

document.addEventListener("DOMContentLoaded", () => {
  if (embeddedParams.get("embed") === "1") {
    document.body.classList.add("is-embedded");
  }

  rewriteMarkdownLinks();
  renderMarkdownPreview();

  const currentPath = window.location.pathname.split("/").pop() || "index.html";
  const currentHash = window.location.hash;

  document.querySelectorAll("[data-nav]").forEach((link) => {
    const target = link.getAttribute("href") || "";
    if (target.endsWith(currentPath) || (currentPath === "" && target.endsWith("index.html"))) {
      link.classList.add("active");
    }
  });

  const sectionLinks = [...document.querySelectorAll(".section-nav a")];
  const sections = sectionLinks
    .map((link) => {
      const id = link.getAttribute("href");
      return id ? document.querySelector(id) : null;
    })
    .filter(Boolean);

  if (currentHash) {
    const active = document.querySelector(`.section-nav a[href="${currentHash}"]`);
    if (active) active.classList.add("active");
  }

  if (!sectionLinks.length || !sections.length) {
    return;
  }

  const observer = new IntersectionObserver(
    (entries) => {
      entries.forEach((entry) => {
        if (!entry.isIntersecting) return;
        const id = `#${entry.target.id}`;
        sectionLinks.forEach((link) => link.classList.toggle("active", link.getAttribute("href") === id));
      });
    },
    {
      rootMargin: "-20% 0px -60% 0px",
      threshold: 0.1,
    }
  );

  sections.forEach((section) => observer.observe(section));
});
