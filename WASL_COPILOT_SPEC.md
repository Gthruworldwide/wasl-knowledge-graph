# Project Specification: Wasl (Celebrity, Athlete & Corporate Wealth Knowledge Graph)

## 1. Context & Product Vision
**Wasl** is a local-first mobile knowledge graph (`com.gthruworldwide.wasl.app`) where all data is stored strictly on the user's device. 
The core purpose of **Wasl** is to track and analyze the wealth of **Athletes (اللاعبين)**, **Artists & Celebrities (الفنانين والمشاهير)**, **Business Figures**, and **Companies (الشركات)**, alongside **Economic News** affecting them.

### Key Domain Features:
- **Multi-Category Wealth Tracking:** Dedicated categorization for Athletes, Artists, Entrepreneurs, and Companies.
- **Wealth Breakdown (مصادر الدخل والتنوع):** Track how wealth is distributed across salaries/contracts, brand endorsements, business ventures, royalties, and investments.
- **Assets & Properties Registry (الممتلكات):** Link high-value assets (Real Estate, Private Jets, Yachts, Stakes in Clubs/Companies, Cars) directly to individuals as connected graph nodes.
- **Weekly Snapshots:** Track weekly net worth updates, new sponsorship deals, box-office/streaming milestones, or transfer news without overwriting historical data.

---

## 2. Database Schema & Data Models

### A. `Entity` (Core Node)
Represents an Athlete, Artist, Company, Luxury Asset/Property, or Economic News item.
- `id`: String (UUID, Primary Key)
- `category`: Enum (`ATHLETE`, `ARTIST`, `BUSINESS_FIGURE`, `COMPANY`, `PROPERTY_ASSET`, `ECONOMIC_NEWS`)
- `name`: String (Indexed for search, e.g., "Cristiano Ronaldo", "Taylor Swift", "Real Madrid CF")
- `subtitle`: String (e.g., "Footballer • Al-Nassr", "Singer-Songwriter", "Tech Conglomerate")
- `nationalityOrOrigin`: String (Nullable)
- `metadataJson`: String (Flexible attributes: e.g., `{"sport": "Football", "club": "Al-Nassr"}` or `{"genre": "Pop", "label": "Republic Records"}`)
- `createdAt`: Timestamp
- `updatedAt`: Timestamp

### B. `WeeklySnapshot` (Time-Series Net Worth & Milestones)
Stores weekly updates for an entity to power trend charts and week-over-week (WoW) comparisons.
- `id`: String (UUID, Primary Key)
- `entityId`: String (Foreign Key -> `Entity.id`, Indexed)
- `weekIdentifier`: String (Format: `YYYY-Www`, e.g., `"2026-W46"`)
- `recordedAt`: Timestamp
- `totalNetWorth`: Double (Nullable — e.g., `850.0` for $850M)
- `currencyUnit`: String (Default: `"USD_M"` for Millions, `"USD_B"` for Billions)
- `wowChangePercent`: Double (Auto-calculated against the previous week's snapshot)
- `summaryNote`: String (Weekly highlight: e.g., "Signed new 2-year endorsement deal" or "World tour revenue milestone")
- `sourceId`: String (Foreign Key -> `Source.id`)

### C. `IncomeStream` (مصادر الدخل وتنوع الثروة)
Breaks down an entity's revenue sources and portfolio diversification percentages.
- `id`: String (UUID, Primary Key)
- `entityId`: String (Foreign Key -> `Entity.id`, Indexed)
- `streamType`: Enum (
  `SALARY_CONTRACT`,      // رواتب وعقود احتراف
  `ENDORSEMENTS_ADS`,     // إعلانات ورعايات
  `ROYALTIES_STREAMING`,  // حقوق ملكية وبث موسيقي/سينمائي
  `TOURS_EVENTS`,         // حفلات وجولات
  `BUSINESS_EQUITY`,      // حصص في شركات ومشاريع خاصة
  `REAL_ESTATE`,          // استثمارات عقارية
  `INVESTMENTS_STOCKS`    // أسهم وصناديق استثمار
)
- `title`: String (e.g., "Nike Lifetime Deal", "Music Catalog Royalties", "CR7 Hotels")
- `estimatedAnnualValue`: Double (Nullable, in `USD_M`)
- `portfolioSharePercent`: Double (Nullable, e.g., `35.0` representing 35% of total wealth/income)
- `lastUpdatedWeek`: String (e.g., `"2026-W46"`)

### D. `EntityRelation` (الممتلكات والروابط - Knowledge Graph)
Connects individuals to their properties, owned companies, sponsors, or impacting economic news.
- `id`: String (UUID, Primary Key)
- `fromEntityId`: String (Foreign Key -> `Entity.id`)
- `toEntityId`: String (Foreign Key -> `Entity.id`)
- `relationType`: Enum (`OWNS_PROPERTY`, `OWNS_STAKE`, `SPONSORED_BY`, `PLAYS_FOR`, `IMPACTED_BY_NEWS`)
- `relationDetail`: String (Nullable — e.g., "100% Ownership • Est. $25M", "15% Equity Stake")

### E. `Source` (Provenance & Feeds)
- `id`: String (UUID, Primary Key)
- `title`: String (e.g., "Forbes Athletes List", "Bloomberg Billionaires", "Weekly Digest W46")
- `url`: String (Nullable)
- `sourceType`: Enum (`MANUAL`, `JSON_IMPORT`, `RSS_FEED`)
- `lastSyncedAt`: Timestamp

---

## 3. Standardized Weekly JSON Import Format
Implement `WeeklyBundleImporter` to parse and upsert this comprehensive JSON format in a single database transaction:

```json
{
  "bundleVersion": "2.0",
  "weekIdentifier": "2026-W46",
  "generatedAt": "2026-11-17T00:00:00Z",
  "source": {
    "title": "Weekly Celebrity & Athlete Wealth Digest - W46",
    "sourceType": "JSON_IMPORT"
  },
  "entities": [
    {
      "id": "ent_athlete_01",
      "category": "ATHLETE",
      "name": "Cristiano Ronaldo",
      "subtitle": "Football • Al-Nassr & Portugal",
      "nationalityOrOrigin": "Portugal",
      "snapshot": {
        "totalNetWorth": 850.5,
        "currencyUnit": "USD_M",
        "summaryNote": "Weekly net worth boosted by commercial partnerships and media channel growth."
      },
      "incomeStreams": [
        {
          "streamType": "SALARY_CONTRACT",
          "title": "Club Playing Contract",
          "estimatedAnnualValue": 215.0,
          "portfolioSharePercent": 45.0
        },
        {
          "streamType": "ENDORSEMENTS_ADS",
          "title": "Global Brand Sponsorships (Nike, Binance, etc.)",
          "estimatedAnnualValue": 65.0,
          "portfolioSharePercent": 30.0
        },
        {
          "streamType": "BUSINESS_EQUITY",
          "title": "Pestana CR7 Hotels & Wellness Clinics",
          "estimatedAnnualValue": 40.0,
          "portfolioSharePercent": 25.0
        }
      ],
      "relations": [
        {
          "targetId": "prop_jet_g650",
          "relationType": "OWNS_PROPERTY",
          "relationDetail": "Gulfstream G650 Private Jet ($73M)"
        },
        {
          "targetId": "prop_madeira_mansion",
          "relationType": "OWNS_PROPERTY",
          "relationDetail": "7-Story Luxury Villa in Funchal ($10M)"
        }
      ]
    },
    {
      "id": "ent_artist_01",
      "category": "ARTIST",
      "name": "Taylor Swift",
      "subtitle": "Music • Singer-Songwriter",
      "nationalityOrOrigin": "USA",
      "snapshot": {
        "totalNetWorth": 1600.0,
        "currencyUnit": "USD_M",
        "summaryNote": "Catalog valuation and touring merchandise continue driving steady weekly gains."
      },
      "incomeStreams": [
        {
          "streamType": "ROYALTIES_STREAMING",
          "title": "Master Recordings & Music Catalog",
          "estimatedAnnualValue": 120.0,
          "portfolioSharePercent": 50.0
        },
        {
          "streamType": "TOURS_EVENTS",
          "title": "Global Stadium Tours & Film Rights",
          "estimatedAnnualValue": 150.0,
          "portfolioSharePercent": 35.0
        },
        {
          "streamType": "REAL_ESTATE",
          "title": "Multi-State Luxury Real Estate Portfolio",
          "estimatedAnnualValue": 15.0,
          "portfolioSharePercent": 15.0
        }
      ]
    },
    {
      "id": "prop_jet_g650",
      "category": "PROPERTY_ASSET",
      "name": "Gulfstream G650 Private Jet",
      "subtitle": "Aviation Asset",
      "snapshot": {
        "totalNetWorth": 73.0,
        "currencyUnit": "USD_M",
        "summaryNote": "Estimated market resale valuation."
      }
    }
  ]
}
```

---

## 4. UI / UX Refinements & Screen Architecture

### Task 1: Home Screen & Empty State Fix
- **Fix Button Redundancy:** When the database is empty, render ONLY the centered `+ Add entity` CTA button and hide the bottom-right FAB. Show the FAB + `Import Weekly JSON` action only when entities exist.
- **Category Filter Chips:** Place a horizontal scrollable `FilterChip` bar under `Search your knowledge`:
  - `All` | `Athletes (اللاعبين)` | `Artists (الفنانين)` | `Companies (الشركات)` | `Properties (الممتلكات)` | `Economic News`
- **Entity Feed Cards:** Each card should display:
  - Name, Category Badge, and Subtitle
  - Formatted Net Worth (e.g., `$850.5M` or `$1.6B`)
  - Week-over-Week badge (`+1.8%` green / `-0.5%` red)
  - Quick tags showing top income source (e.g., `45% Contracts • 30% Ads`)

### Task 2: Rich Entity Profile Screen (شاشة تفاصيل الثروة)
Organize the detail screen into 4 clean sections:
1. **Wealth Summary Header:** Total Net Worth, WoW change percentage, and historical line chart across `weekIdentifier`s.
2. **Diversification & Income Breakdown (التنوع ومصادر الدخل):**
   - A horizontal stacked bar or donut chart showing `portfolioSharePercent` by `streamType`.
   - List of income streams with estimated annual yield and share percentage.
3. **Properties & Holdings (الممتلكات والأصول):**
   - Cards/chips for all linked `PROPERTY_ASSET` and `COMPANY` stakes (`OWNS_PROPERTY`, `OWNS_STAKE`), clickable to navigate to that asset's own node.
4. **Weekly Updates & News Feed:**
   - Chronological log of weekly `summaryNote`s and linked `ECONOMIC_NEWS` items with source citations.

### Task 3: Manual Add / Edit Bottom Sheet
- Allow users to manually add an Athlete, Artist, Company, or Property, attach initial `IncomeStream` percentages, and link existing properties without needing a JSON file.

---

## 5. Step-by-Step Execution Plan for GitHub Copilot
1. **Step 1 (Database & Models):** Implement `Entity`, `WeeklySnapshot`, `IncomeStream`, `EntityRelation`, and `Source` tables/models with DAOs and automatic WoW calculation.
2. **Step 2 (JSON Importer & Seed Data):** Implement `WeeklyBundleImporter` supporting `WASL_COPILOT_SPEC` v2.0 JSON and bundle a sample seed JSON (including Athletes, Artists, Companies, and Properties) in app assets.
3. **Step 3 (Home Screen Refactor):** Fix the duplicate `+ Add entity` button on the empty state, add category filter chips, and build the wealth summary cards.
4. **Step 4 (Entity Detail & Charts):** Build the profile view featuring the historical trend chart, income diversification breakdown bar/chart, and clickable properties/holdings graph links.