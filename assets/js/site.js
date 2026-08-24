(() => {
  const root = document.documentElement;
  const body = document.body;
  const navToggle = document.querySelector('.nav-toggle');
  const navClose = document.querySelector('[data-nav-close]');
  const themePicker = document.querySelector('#theme-picker');
  const backToTop = document.querySelector('.back-to-top');
  const sidebar = document.querySelector('#site-sidebar');
  const searchRoot = document.querySelector('[data-site-search]');
  const searchInput = document.querySelector('#site-search-input');
  const searchResults = document.querySelector('#site-search-results');
  const searchStatus = document.querySelector('#site-search-status');

  document.querySelectorAll('img[src$="/assets/images/product_banner.png"], img[src$="assets/images/product_banner.png"]').forEach((image) => {
    image.setAttribute('width', '1280');
    image.setAttribute('height', '320');
  });

  if (sidebar) {
    const sidebarScrollKey = 'copy-github-repo-sidebar-scroll';
    let restoredSidebarPosition = false;

    try {
      const savedPosition = sessionStorage.getItem(sidebarScrollKey);
      if (savedPosition !== null) {
        const scrollTop = Number(savedPosition);
        if (Number.isFinite(scrollTop)) {
          sidebar.scrollTop = scrollTop;
          restoredSidebarPosition = true;
        }
      }
    } catch {
      // Session storage can be unavailable in hardened browser contexts.
    }

    if (!restoredSidebarPosition) {
      sidebar.querySelector('.docs-nav a.is-active')?.scrollIntoView({ block: 'nearest' });
    }

    const saveSidebarPosition = () => {
      try {
        sessionStorage.setItem(sidebarScrollKey, String(sidebar.scrollTop));
      } catch {
        // Navigation still works when session storage is unavailable.
      }
    };

    sidebar.addEventListener('scroll', saveSidebarPosition, { passive: true });
    sidebar.querySelectorAll('.docs-nav a[href]').forEach((link) => link.addEventListener('click', saveSidebarPosition));
    window.addEventListener('pagehide', saveSidebarPosition);
  }

  const isCompactNavigation = () => window.matchMedia('(max-width: 980px)').matches;
  const getNavigationFocusables = () => {
    if (!navToggle || !sidebar) return [];
    const sidebarFocusables = Array.from(sidebar.querySelectorAll('a[href], button:not([disabled]), [tabindex]:not([tabindex="-1"])'));
    return [navToggle, ...sidebarFocusables].filter((element) => !element.hidden && element.getClientRects().length > 0);
  };

  const closeNavigation = (restoreFocus = false) => {
    const wasOpen = body.classList.contains('nav-open');
    body.classList.remove('nav-open');
    navToggle?.setAttribute('aria-expanded', 'false');
    navToggle?.setAttribute('aria-label', 'Open navigation');
    if (restoreFocus && wasOpen) navToggle?.focus();
  };

  const scrollActiveNavigationIntoView = () => {
    if (!sidebar || !isCompactNavigation()) return;
    const activeLink = sidebar.querySelector('.docs-nav a.is-active');
    if (!activeLink) return;

    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    activeLink.scrollIntoView({
      behavior: reduceMotion ? 'auto' : 'smooth',
      block: 'center'
    });
  };

  navToggle?.addEventListener('click', () => {
    const isOpen = body.classList.toggle('nav-open');
    navToggle.setAttribute('aria-expanded', String(isOpen));
    navToggle.setAttribute('aria-label', isOpen ? 'Close navigation' : 'Open navigation');
    if (isOpen) {
      requestAnimationFrame(() => {
        scrollActiveNavigationIntoView();
        const activeLink = sidebar?.querySelector('.docs-nav a.is-active');
        (activeLink || sidebar?.querySelector('.docs-nav a[href]'))?.focus();
      });
    }
  });
  navClose?.addEventListener('click', () => closeNavigation(true));

  const closeSearch = () => {
    if (!searchResults || !searchInput) return;
    searchResults.hidden = true;
    searchInput.setAttribute('aria-expanded', 'false');
    searchInput.removeAttribute('aria-activedescendant');
  };

  document.addEventListener('keydown', (event) => {
    if (event.key === 'Escape') {
      const navigationWasOpen = body.classList.contains('nav-open');
      closeNavigation(navigationWasOpen);
      closeSearch();
      return;
    }

    if (event.key === 'Tab' && body.classList.contains('nav-open') && isCompactNavigation()) {
      const focusables = getNavigationFocusables();
      if (!focusables.length) return;
      const first = focusables[0];
      const last = focusables[focusables.length - 1];
      const active = document.activeElement;

      if (event.shiftKey && (active === first || !focusables.includes(active))) {
        event.preventDefault();
        last.focus();
      } else if (!event.shiftKey && active === last) {
        event.preventDefault();
        first.focus();
      }
    }
  });

  window.addEventListener('resize', () => {
    if (!isCompactNavigation() && body.classList.contains('nav-open')) closeNavigation(false);
  });

  if (themePicker) {
    themePicker.value = root.dataset.theme || 'light';
    themePicker.addEventListener('change', () => {
      const theme = themePicker.value;
      if (theme === 'light') delete root.dataset.theme;
      else root.dataset.theme = theme;
      try { localStorage.setItem('copy-github-repo-theme', theme); } catch {}
    });
  }

  const updateReadingProgress = () => {
    const scrollTop = window.scrollY || document.documentElement.scrollTop;
    const scrollable = document.documentElement.scrollHeight - window.innerHeight;
    const progress = scrollable > 0 ? Math.min(100, Math.max(0, scrollTop / scrollable * 100)) : 0;
    root.style.setProperty('--reading-progress', `${progress}%`);
    if (backToTop) {
      const visible = scrollTop > 500;
      backToTop.hidden = !visible;
      backToTop.classList.toggle('is-visible', visible);
    }
  };
  window.addEventListener('scroll', updateReadingProgress, { passive: true });
  window.addEventListener('resize', updateReadingProgress);
  updateReadingProgress();
  backToTop?.addEventListener('click', () => {
    const reduceMotion = window.matchMedia('(prefers-reduced-motion: reduce)').matches;
    window.scrollTo({ top: 0, behavior: reduceMotion ? 'auto' : 'smooth' });
  });

  if (searchRoot && searchInput && searchResults) {
    let indexPromise;
    let selected = -1;
    const normalize = (value) => value.toLowerCase().replace(/\s+/g, ' ').trim();
    const loadIndex = async () => {
      const indexUrl = searchRoot.dataset.searchIndex;
      if (!indexUrl) return [];
      try {
        const response = await fetch(indexUrl, { credentials: 'same-origin' });
        if (!response.ok) return [];
        const pages = await response.json();
        return pages.map((page) => ({
          ...page,
          titleSearch: normalize(page.title || ''),
          textSearch: normalize(page.text || '')
        }));
      } catch {
        return [];
      }
    };
    const ensureIndex = () => indexPromise ||= loadIndex();
    const setSelected = (index) => {
      const options = Array.from(searchResults.querySelectorAll('[role="option"]'));
      selected = options.length ? Math.max(0, Math.min(options.length - 1, index)) : -1;
      options.forEach((option, optionIndex) => {
        const isSelected = optionIndex === selected;
        option.classList.toggle('is-selected', isSelected);
        option.setAttribute('aria-selected', String(isSelected));
      });
      if (selected >= 0) {
        searchInput.setAttribute('aria-activedescendant', options[selected].id);
        options[selected].scrollIntoView({ block: 'nearest' });
      } else {
        searchInput.removeAttribute('aria-activedescendant');
      }
    };
    const render = (matches, query) => {
      searchResults.replaceChildren();
      selected = -1;
      searchInput.removeAttribute('aria-activedescendant');
      if (!query) {
        closeSearch();
        if (searchStatus) searchStatus.textContent = '';
        return;
      }
      if (!matches.length) {
        const empty = document.createElement('div');
        empty.className = 'site-search__empty';
        empty.id = 'site-search-option-empty';
        empty.setAttribute('role', 'option');
        empty.setAttribute('aria-disabled', 'true');
        empty.setAttribute('aria-selected', 'false');
        empty.textContent = 'No matching documentation found.';
        searchResults.appendChild(empty);
        if (searchStatus) searchStatus.textContent = 'No matching documentation found.';
      } else {
        matches.slice(0, 8).forEach((page, index) => {
          const link = document.createElement('a');
          link.className = 'site-search__result';
          link.href = page.url;
          link.id = `site-search-option-${index}`;
          link.tabIndex = -1;
          link.setAttribute('role', 'option');
          link.setAttribute('aria-selected', 'false');
          const title = document.createElement('strong');
          title.textContent = page.title;
          const snippet = document.createElement('span');
          snippet.textContent = page.text.slice(0, 180) + (page.text.length > 180 ? '…' : '');
          link.append(title, snippet);
          searchResults.appendChild(link);
        });
        if (searchStatus) searchStatus.textContent = `${Math.min(matches.length, 8)} search result${Math.min(matches.length, 8) === 1 ? '' : 's'} available.`;
      }
      searchResults.hidden = false;
      searchInput.setAttribute('aria-expanded', 'true');
    };
    const runSearch = async () => {
      const query = normalize(searchInput.value);
      if (!query) return render([], '');
      const terms = query.split(' ');
      const pages = await ensureIndex();
      const matches = pages.map((page) => ({
        ...page,
        score: terms.filter((term) => page.titleSearch.includes(term)).length * 4 + terms.filter((term) => page.textSearch.includes(term)).length
      })).filter((page) => page.score > 0 && terms.every((term) => page.titleSearch.includes(term) || page.textSearch.includes(term)))
        .sort((a, b) => b.score - a.score || a.title.localeCompare(b.title));
      render(matches, searchInput.value.trim());
    };
    searchInput.addEventListener('focus', ensureIndex);
    searchInput.addEventListener('input', runSearch);
    searchInput.addEventListener('keydown', (event) => {
      const links = Array.from(searchResults.querySelectorAll('.site-search__result'));
      if (event.key === 'ArrowDown' && links.length) {
        event.preventDefault();
        setSelected(selected < 0 ? 0 : selected + 1);
      } else if (event.key === 'ArrowUp' && links.length) {
        event.preventDefault();
        setSelected(selected < 0 ? links.length - 1 : selected - 1);
      } else if (event.key === 'Enter' && links.length) {
        event.preventDefault();
        location.href = links[Math.max(0, selected)]?.href;
      }
    });
    document.addEventListener('click', (event) => {
      if (!searchRoot.contains(event.target)) closeSearch();
    });
  }

  const content = document.querySelector('.content-prose');
  const contentWrap = document.querySelector('.content-wrap');

  if (content && contentWrap) {
    const pageTitle = content.querySelector('h1');
    const sectionHeadings = Array.from(content.querySelectorAll('h2, h3'));
    const headings = pageTitle ? [pageTitle, ...sectionHeadings] : sectionHeadings;

    if (sectionHeadings.length >= 2 && headings.length > 0) {
      const usedIds = new Set(Array.from(document.querySelectorAll('[id]')).map((element) => element.id));
      const slugify = (value) => value
        .toLowerCase()
        .trim()
        .replace(/[^a-z0-9\s-]/g, '')
        .replace(/\s+/g, '-')
        .replace(/-+/g, '-');

      headings.forEach((heading, index) => {
        if (!heading.id) {
          const baseId = heading.tagName === 'H1' ? 'page-top' : (slugify(heading.textContent) || `section-${index + 1}`);
          let id = baseId;
          let suffix = 2;
          while (usedIds.has(id)) {
            id = `${baseId}-${suffix}`;
            suffix += 1;
          }
          heading.id = id;
        }
        usedIds.add(heading.id);
      });

      const aside = document.createElement('aside');
      aside.className = 'on-this-page';
      aside.setAttribute('aria-label', 'On this page');

      const title = document.createElement('p');
      title.className = 'on-this-page__title';
      title.textContent = 'On this page';
      aside.appendChild(title);

      const list = document.createElement('ul');
      const links = [];
      headings.forEach((heading) => {
        const item = document.createElement('li');
        item.className = `toc-level-${heading.tagName === 'H1' ? '1' : heading.tagName === 'H3' ? '3' : '2'}`;
        const link = document.createElement('a');
        link.href = `#${heading.id}`;
        link.textContent = heading.textContent.trim();
        link.dataset.targetId = heading.id;
        item.appendChild(link);
        list.appendChild(item);
        links.push(link);
      });
      aside.appendChild(list);
      document.body.appendChild(aside);
      contentWrap.classList.add('has-on-this-page');

      const setActiveLink = (id) => links.forEach((link) => {
        const isActive = link.dataset.targetId === id;
        link.classList.toggle('is-active', isActive);
        if (isActive) link.setAttribute('aria-current', 'location');
        else link.removeAttribute('aria-current');
      });
      const updateActiveLink = () => {
        const offset = (parseFloat(getComputedStyle(root).getPropertyValue('--header-height')) || 68) + 32;
        let active = headings[0];
        for (const heading of headings) {
          if (heading.getBoundingClientRect().top <= offset) active = heading;
          else break;
        }
        setActiveLink(active.id);
      };

      window.addEventListener('scroll', updateActiveLink, { passive: true });
      window.addEventListener('resize', updateActiveLink);
      updateActiveLink();
    }
  }

  const resetIcon = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M4 12a8 8 0 1 0 2.34-5.66L4 8.68M4 4v4.68h4.68" fill="none" stroke="currentColor" stroke-width="2" stroke-linecap="round" stroke-linejoin="round"/></svg>';
  const initializeDiagram = (wrapper) => {
    if (wrapper.dataset.interactionsReady === 'true') return;
    const canvas = wrapper.querySelector('.mermaid');
    if (!canvas) return;
    wrapper.dataset.interactionsReady = 'true';
    wrapper.classList.add('is-interactive');
    let scale = 1, x = 0, y = 0, dragging = false, startX = 0, startY = 0, baseX = 0, baseY = 0;
    const apply = () => { canvas.style.transform = `translate(${x}px, ${y}px) scale(${scale})`; };
    const reset = () => { scale = 1; x = 0; y = 0; apply(); };
    const button = document.createElement('button');
    button.className = 'mermaid-diagram__reset'; button.type = 'button'; button.innerHTML = resetIcon;
    button.setAttribute('aria-label', 'Reset diagram view'); button.setAttribute('title', 'Reset diagram view');
    button.addEventListener('click', (event) => { event.stopPropagation(); reset(); });
    const fullscreen = wrapper.querySelector('.mermaid-diagram__fullscreen');
    fullscreen ? wrapper.insertBefore(button, fullscreen) : wrapper.prepend(button);
    wrapper.addEventListener('wheel', (event) => {
      if (event.target.closest('button')) return;
      event.preventDefault();
      const previous = scale; scale = Math.min(4, Math.max(.5, scale * (event.deltaY < 0 ? 1.12 : .89)));
      const ratio = scale / previous; const rect = wrapper.getBoundingClientRect(); const px = event.clientX - rect.left; const py = event.clientY - rect.top;
      x = px - ((px - x) * ratio); y = py - ((py - y) * ratio); apply();
    }, { passive: false });
    wrapper.addEventListener('pointerdown', (event) => {
      if (event.button !== 0 || event.target.closest('button')) return;
      dragging = true; startX = event.clientX; startY = event.clientY; baseX = x; baseY = y; wrapper.classList.add('is-dragging'); wrapper.setPointerCapture(event.pointerId);
    });
    wrapper.addEventListener('pointermove', (event) => { if (dragging) { x = baseX + event.clientX - startX; y = baseY + event.clientY - startY; apply(); } });
    const stop = (event) => { if (!dragging) return; dragging = false; wrapper.classList.remove('is-dragging'); if (wrapper.hasPointerCapture?.(event.pointerId)) wrapper.releasePointerCapture(event.pointerId); };
    wrapper.addEventListener('pointerup', stop); wrapper.addEventListener('pointercancel', stop); wrapper.addEventListener('dblclick', reset);
  };
  const initializeAll = () => document.querySelectorAll('.mermaid-diagram').forEach(initializeDiagram);
  initializeAll();
  new MutationObserver(initializeAll).observe(document.body, { childList: true, subtree: true });
})();
