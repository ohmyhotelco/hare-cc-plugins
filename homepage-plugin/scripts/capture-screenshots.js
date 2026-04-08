#!/usr/bin/env node

/**
 * Captures per-section screenshots from a running Astro preview server using Playwright.
 *
 * Usage:
 *   node capture-screenshots.js --url <base-url> --output-dir <path> --sections '<json-array>'
 *
 * Arguments:
 *   --url         Base URL of the running preview server (e.g., http://localhost:4322)
 *   --output-dir  Directory to save screenshot PNGs
 *   --sections    JSON array of section descriptors:
 *                 [{"type":"HeroSection","selector":"[data-section=HeroSection]","page":"/"}]
 *
 * Output:
 *   Saves one PNG per section: <output-dir>/<SectionType>.png
 *   Exits with code 0 on success, 1 on failure.
 *
 * Requirements:
 *   - playwright (pnpm add -D playwright && npx playwright install chromium)
 */

const { parseArgs } = require("node:util");
const { mkdir } = require("node:fs/promises");
const path = require("node:path");

async function main() {
  const { values } = parseArgs({
    options: {
      url: { type: "string" },
      "output-dir": { type: "string" },
      sections: { type: "string" },
    },
  });

  const baseUrl = values.url;
  const outputDir = values["output-dir"];
  const sectionsJson = values.sections;

  if (!baseUrl || !outputDir || !sectionsJson) {
    console.error(
      "Usage: node capture-screenshots.js --url <url> --output-dir <dir> --sections '<json>'"
    );
    process.exit(1);
  }

  let sections;
  try {
    sections = JSON.parse(sectionsJson);
  } catch {
    console.error("Error: --sections must be valid JSON");
    process.exit(1);
  }

  // Check Playwright availability
  let chromium;
  try {
    ({ chromium } = require("playwright"));
  } catch {
    console.error(
      "Error: playwright is not installed.\n" +
        "Install it with: pnpm add -D playwright && npx playwright install chromium"
    );
    process.exit(1);
  }

  await mkdir(outputDir, { recursive: true });

  const browser = await chromium.launch();
  const context = await browser.newContext({
    viewport: { width: 1440, height: 900 },
  });

  // Group sections by page path for efficient navigation
  const byPage = new Map();
  for (const section of sections) {
    const pagePath = section.page || "/";
    if (!byPage.has(pagePath)) byPage.set(pagePath, []);
    byPage.get(pagePath).push(section);
  }

  const results = { captured: [], skipped: [], errors: [] };

  for (const [pagePath, pageSections] of byPage) {
    const page = await context.newPage();
    const url = new URL(pagePath, baseUrl).href;

    try {
      await page.goto(url, { waitUntil: "networkidle", timeout: 30000 });
    } catch (err) {
      console.error(`Failed to navigate to ${url}: ${err.message}`);
      for (const s of pageSections) {
        results.errors.push({ type: s.type, error: `Navigation failed: ${err.message}` });
      }
      await page.close();
      continue;
    }

    // Wait for page to stabilize (fonts, images)
    await page.waitForTimeout(1000);

    for (const section of pageSections) {
      const selector =
        section.selector || `[data-section="${section.type}"]`;
      const outputPath = path.join(outputDir, `${section.type}.png`);

      try {
        const element = await page.$(selector);
        if (!element) {
          // Fallback: try nth <section> element by index if provided
          if (typeof section.index === "number") {
            const allSections = await page.$$("section, header, footer");
            if (allSections[section.index]) {
              await allSections[section.index].screenshot({ path: outputPath });
              results.captured.push(section.type);
              console.log(`Captured (by index ${section.index}): ${section.type}`);
              continue;
            }
          }
          results.skipped.push({
            type: section.type,
            reason: `Selector not found: ${selector}`,
          });
          console.warn(`Skipped: ${section.type} — selector not found`);
          continue;
        }

        await element.screenshot({ path: outputPath });
        results.captured.push(section.type);
        console.log(`Captured: ${section.type}`);
      } catch (err) {
        results.errors.push({ type: section.type, error: err.message });
        console.error(`Error capturing ${section.type}: ${err.message}`);
      }
    }

    await page.close();
  }

  await browser.close();

  // Print summary
  console.log("\n--- Screenshot Capture Summary ---");
  console.log(`Captured: ${results.captured.length}`);
  console.log(`Skipped:  ${results.skipped.length}`);
  console.log(`Errors:   ${results.errors.length}`);

  // Write results JSON for the agent to read
  const resultsPath = path.join(outputDir, "capture-results.json");
  const { writeFile } = require("node:fs/promises");
  await writeFile(resultsPath, JSON.stringify(results, null, 2));

  process.exit(results.errors.length > 0 ? 1 : 0);
}

main().catch((err) => {
  console.error(`Fatal error: ${err.message}`);
  process.exit(1);
});
