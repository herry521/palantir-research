const embeddedParams = new URLSearchParams(window.location.search);
if (embeddedParams.get("embed") === "1") {
  document.documentElement.classList.add("is-embedded-root");
}

document.addEventListener("DOMContentLoaded", () => {
  if (embeddedParams.get("embed") === "1") {
    document.body.classList.add("is-embedded");
  }

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
