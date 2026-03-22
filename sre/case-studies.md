# Real-World SRE Case Studies

[← SRE Home](README.md) | [← Main](../README.md)

All links sourced directly from [howtheysre](../resources/howtheysre/README.md) — no summaries invented.

---

## Airbnb

**Key topics:** incident management, Kubernetes scaling, security, data protection

- [Automated Incident Management Through Slack](https://medium.com/airbnb-engineering/incident-management-ae863dc5d47f)
- [Alerting Framework at Airbnb](https://medium.com/airbnb-engineering/alerting-framework-at-airbnb-35ba48df894f)
- [When The Cloud Gets Dark — How Amazon's Outage Affected Airbnb](https://medium.com/airbnb-engineering/when-the-cloud-gets-dark-how-amazons-outage-affected-airbnb-66eaf8c0f162)
- [Dynamic Kubernetes Cluster Scaling at Airbnb](https://medium.com/airbnb-engineering/dynamic-kubernetes-cluster-scaling-at-airbnb-d79ae3afa132)
- [Production Secret Management at Airbnb](https://medium.com/airbnb-engineering/production-secret-management-at-airbnb-ad230e1bc0f6)
- [Detecting Vulnerabilities With Vulnture](https://medium.com/airbnb-engineering/detecting-vulnerabilities-with-vulnture-f5f23387f6ec)
- [Automating Data Protection at Scale, Part 1](https://medium.com/airbnb-engineering/automating-data-protection-at-scale-part-1-c74909328e08) · [Part 2](https://medium.com/airbnb-engineering/automating-data-protection-at-scale-part-2-c2b8d2068216) · [Part 3](https://medium.com/airbnb-engineering/automating-data-protection-at-scale-part-3-34e592c45d46)

---

## Booking.com

**Key topics:** reliability/product collaboration, incident retrospectives, SLOs for data-intensive services

- [How Reliability and Product Teams Collaborate at Booking.com](https://medium.com/booking-com-infrastructure/how-reliability-and-product-teams-collaborate-at-booking-com-f6c317cc0aeb)
- [Incidents, fixes, and the day after](https://medium.com/booking-com-infrastructure/incidents-fixes-and-the-day-after-c5d9aeae28c3)
- [Troubleshooting: A journey into the unknown](https://medium.com/booking-com-infrastructure/troubleshooting-a-journey-into-the-unknown-e31b524fa86)
- 📺 [SLOs for Data-Intensive Services](https://www.usenix.org/conference/srecon19emea/presentation/fouquet) — SREcon19
- 📺 [Sailing the Database Seas: Applying SRE Principles at Scale](https://www.usenix.org/conference/srecon24emea/presentation/androulidakis) — SREcon24

---

## Capital One

**Key topics:** chaos engineering, canary deployments, cloud resiliency, incident security

- [The 3 R's of SREs: Resiliency, Recovery & Reliability](https://medium.com/capital-one-tech/the-3-rs-of-sres-resiliency-recovery-reliability-5f2f5360a91b)
- [5 Steps to Getting Your App Chaos Ready](https://medium.com/capital-one-tech/5-steps-to-getting-your-app-chaos-ready-capital-one-a5b7b3cb8e09)
- [Embrace the Chaos … Engineering](https://medium.com/capital-one-tech/embrace-the-chaos-engineering-203fd6fc6ff7)
- [3 Lessons Learned From Implementing Chaos Engineering at Enterprise](https://medium.com/capital-one-tech/3-lessons-learned-from-implementing-chaos-engineering-at-enterprise-28eb3ffecc57)
- [Continuous Chaos — Introducing Chaos Engineering into DevOps Practices](https://medium.com/capital-one-tech/continuous-chaos-introducing-chaos-engineering-into-devops-practices-75757e1cca6d)
- [Deploying with Confidence — Canary Deployments on AWS](https://medium.com/capital-one-tech/deploying-with-confidence-strategies-for-canary-deployments-on-aws-7cab3798823e)
- [Architecting for Resiliency](https://medium.com/capital-one-tech/architecting-for-resiliency-9ec663db5c94)
- [Capital One Data Breach — case study (MIT)](http://web.mit.edu/smadnick/www/wp/2020-16.pdf) — security incident post-analysis

---

## Dropbox

**Key topics:** Python monolith to managed platform, build health automation, monitoring

- [Atlas: Our journey from a Python monolith to a managed platform](https://dropbox.tech/infrastructure/atlas--our-journey-from-a-python-monolith-to-a-managed-platform)
- [Monitoring server applications with Vortex](https://dropbox.tech/infrastructure/monitoring-server-applications-with-vortex)
- [Athena: Our automated build health management system](https://dropbox.tech/infrastructure/athena-our-automated-build-health-management-system)
- [SRE Career Framework](https://dropbox.github.io/dbx-career-framework/)
- 📺 [Service Discovery Challenges at Scale](https://www.usenix.org/conference/srecon19americas/presentation/nigmatullin) — SREcon19

---

## eBay

**Key topics:** Kafka DR, JVM triage, zero-downtime deployments, fault injection

- [Resiliency and Disaster Recovery with Kafka](https://tech.ebayinc.com/engineering/resiliency-and-disaster-recovery-with-kafka/)
- [SRE Case Study: Triaging a Non-Heap JVM Out of Memory Issue](https://tech.ebayinc.com/engineering/sre-case-study-triage-a-non-heap-jvm-out-of-memory-issue/)
- [SRE Case Study: Mysterious Traffic Imbalance](https://tech.ebayinc.com/engineering/sre-case-study-mysterious-traffic-imbalance/)
- [Zero Downtime, Instant Deployment and Rollback](https://tech.ebayinc.com/engineering/zero-downtime-instant-deployment-and-rollback/)
- [How eBay's Notification Platform Used Fault Injection in New Ways](https://innovation.ebayinc.com/tech/engineering/how-ebays-notification-platform-used-fault-injection-in-new-ways/)

---

## Etsy

**Key topics:** blameless postmortems (origin), on-call measurement, high-traffic preparation

- [Blameless PostMortems and a Just Culture](https://codeascraft.com/2012/05/22/blameless-postmortems/) — the founding post
- [Etsy's Debriefing Facilitation Guide for Blameless Postmortems](https://codeascraft.com/2016/11/17/debriefing-facilitation-guide/)
- [Opsweekly: Measuring on-call experience with alert classification](https://codeascraft.com/2014/06/19/opsweekly-measuring-on-call-experience-with-alert-classification/)
- [How Etsy Prepared for Historic Volumes of Holiday Traffic in 2020](https://codeascraft.com/2021/02/25/how-etsy-prepared-for-historic-volumes-of-holiday-traffic-in-2020/)
- [Measure Anything, Measure Everything](https://codeascraft.com/2011/02/15/measure-anything-measure-everything/)
- [Demystifying Site Outages](https://blog.etsy.com/news/2012/demystifying-site-outages/)
- 📺 [Velocity 09: 10+ Deploys Per Day — Dev and Ops Cooperation at Flickr/Etsy](https://www.youtube.com/watch?v=LdOe18KhtT4) — the talk that launched DevOps

---

## GitHub

**Key topics:** availability reports (public), deployment reliability, ChatOps, on-call culture, OpenTelemetry

**Engineering posts:**
- [Deployment reliability at GitHub](https://github.blog/2021-02-03-deployment-reliability-at-github/)
- [Improving how we deploy GitHub](https://github.blog/2021-01-25-improving-how-we-deploy-github/)
- [Building On-Call Culture at GitHub](https://github.blog/2021-01-06-building-on-call-culture-at-github/)
- [Using ChatOps to help Actions on-call engineers](https://github.blog/2021-12-01-using-chatops-to-help-actions-on-call-engineers/)
- [Why (and how) GitHub is adopting OpenTelemetry](https://github.blog/2021-05-26-why-and-how-github-is-adopting-opentelemetry/)
- [Partitioning GitHub's relational databases to handle scale](https://github.blog/2021-09-27-partitioning-githubs-relational-databases-scale/)
- [Reducing flaky builds by 18x](https://github.blog/2020-12-16-reducing-flaky-builds-by-18x/)
- [MySQL High Availability at GitHub](https://github.blog/2018-06-20-mysql-high-availability-at-github/)
- [How we improved availability through iterative simplification](https://github.blog/engineering/engineering-principles/how-we-improved-availability-through-iterative-simplification/)
- [How GitHub uses merge queue to ship hundreds of changes every day](https://github.blog/engineering/engineering-principles/how-github-uses-merge-queue-to-ship-hundreds-of-changes-every-day/)

**Availability reports (public postmortems):**
- [February 28th DDoS Incident Report](https://github.blog/2018-03-01-ddos-incident-report/)
- [October 21 post-incident analysis](https://github.blog/2018-10-30-oct21-post-incident-analysis/)
- [February service disruptions post-incident analysis](https://github.blog/2020-03-26-february-service-disruptions-post-incident-analysis/)
- [Monthly availability reports (2020–2024)](https://github.blog/news-insights/company-news/github-availability-report-august-2024/) — GitHub publishes these every month

---

## Google

**Key topics:** SRE as a discipline, error budgets, SLOs, ML reliability, on-call scaling

- [SRE Practices & Processes](https://sre.google/resources/#practicesandprocesses)
- [How SRE teams are organized, and how to get started](https://cloud.google.com/blog/products/devops-sre/how-sre-teams-are-organized-and-how-to-get-started)
- [Three months, 30x demand: How we scaled Google Meet during COVID-19](https://cloud.google.com/blog/products/g-suite/keeping-google-meet-ahead-of-usage-demand-during-covid-19)
- [Accelerating incident response using generative AI](https://security.googleblog.com/2024/04/accelerating-incident-response-using.html)
- [Google site reliability using Go](https://go.dev/solutions/google/sitereliability)

**SREcon talks:**
- 📺 [What's the Difference Between DevOps and SRE?](https://youtu.be/uTEL8Ff1Zvk) — Seth Vargo & Liz Fong-Jones
- 📺 [Risk and Error Budgets](https://youtu.be/y2ILKr8kCJU) — Seth Vargo & Liz Fong-Jones
- 📺 [Must Watch — Google SRE YouTube Playlist](https://www.youtube.com/playlist?list=PLIivdWyY5sqJrKl7D2u-gmis8h9K66qoj)
- 📺 [Zero Touch Prod: Towards Safer Production Environments](https://www.usenix.org/conference/srecon19emea/presentation/czapinski)
- 📺 [Scaling SRE Organizations: The Journey from 1 to Many Teams](https://www.usenix.org/conference/srecon19americas/presentation/franco)
- 📺 [The Map Is Not the Territory: How SLOs Lead Us Astray](https://www.usenix.org/conference/srecon19emea/presentation/desai)

---

## Pinterest

**Key topics:** Kubernetes scaling, distributed tracing, auto-scaling, CI performance, observability

- [Scaling Kubernetes with Assurance at Pinterest](https://medium.com/pinterest-engineering/scaling-kubernetes-with-assurance-at-pinterest-a23f821168da)
- [Auto scaling Pinterest](https://medium.com/pinterest-engineering/auto-scaling-pinterest-df1d2beb4d64)
- [Distributed tracing at Pinterest with new open source tools](https://medium.com/pinterest-engineering/distributed-tracing-at-pinterest-with-new-open-source-tools-a4f8a5562f6b)
- [How we designed our CI System to be more than 50% Faster](https://medium.com/pinterest-engineering/how-we-designed-our-continuous-integration-system-to-be-more-than-50-faster-b70a59342fe2)
- [Ensuring High Availability of Ads Realtime Streaming Services](https://medium.com/pinterest-engineering/ensuring-high-availability-of-ads-realtime-streaming-services-ea3889420490)
- [Upgrading Pinterest operational metrics](https://medium.com/pinterest-engineering/upgrading-pinterest-operational-metrics-8718d058079a)
- 📺 [Evolution of Observability Tools at Pinterest](https://www.usenix.org/conference/srecon19emea/presentation/abbas) — SREcon19

---

## Shopify

**Key topics:** high-traffic event resiliency, capacity planning, game days, ChatOps incidents, DNS

- [Resiliency Planning for High-Traffic Events](https://shopify.engineering/resiliency-planning-for-high-traffic-events)
- [Capacity Planning at Scale](https://shopify.engineering/capacity-planning-shopify)
- [Four Steps to Creating Effective Game Day Tests](https://shopify.engineering/four-steps-creating-effective-game-day-tests)
- [Implementing ChatOps into our Incident Management Procedure](https://shopify.engineering/implementing-chatops-into-our-incident-management-procedure)
- [Using DNS Traffic Management to Add Resiliency to Shopify's Services](https://shopify.engineering/using-dns-traffic-management-add-resiliency-shopify-services)
- [StatsD at Shopify](https://shopify.engineering/17488320-statsd-at-shopify)
- 📺 [Expect the Unexpected: Preparing SRE Teams for Responding to Novel Failures](https://www.usenix.org/conference/srecon19emea/presentation/arthorne) — SREcon19
- 📺 [Advanced Napkin Math: Estimating System Performance from First Principles](https://www.usenix.org/conference/srecon19emea/presentation/eskildsen) — SREcon19

---

## Slack

**Key topics:** public incident reports, chaos engineering, deploy pipeline, observability cost

- [Slack's Incident on 2-22-22](https://slack.engineering/slacks-incident-on-2-22-22/) — detailed public postmortem
- [Slack's Outage on January 4th 2021](https://slack.engineering/slacks-outage-on-january-4th-2021/) — detailed public postmortem
- [A Terrible, Horrible, No-Good, Very Bad Day at Slack](https://slack.engineering/a-terrible-horrible-no-good-very-bad-day-at-slack/)
- [Disasterpiece Theater: Slack's process for approachable Chaos Engineering](https://slack.engineering/disasterpiece-theater-slacks-process-for-approachable-chaos-engineering/)
- [Deploys at Slack](https://slack.engineering/deploys-at-slack/)
- [Infrastructure Observability for Changing the Spend Curve](https://slack.engineering/infrastructure-observability-for-changing-the-spend-curve/)
- 📺 [What Breaks Our Systems: A Taxonomy of Black Swans](https://www.usenix.org/conference/srecon19americas/presentation/nolan-taxonomy) — SREcon19

---

## Spotify

**Key topics:** Kubernetes developer experience, incident response automation, tracing performance

- [Automated Incident Response Infrastructure in GCP](https://engineering.atspotify.com/2019/04/04/whacking-a-million-moles-automated-incident-response-infrastructure-in-gcp/)
- [Designing a Better Kubernetes Experience for Developers](https://engineering.atspotify.com/2021/03/01/designing-a-better-kubernetes-experience-for-developers/)
- [Techbytes: What The Industry Misses About Incidents and What You Can Do](https://engineering.atspotify.com/2020/02/26/techbytes-what-the-industry-misses-about-incidents-and-what-you-can-do/)
- 📺 [Tracing, Fast and Slow: Digging into and Improving Your Web Service's Performance](https://www.usenix.org/conference/srecon19americas/presentation/root) — SREcon19

---

## Stripe

**Key topics:** canonical log lines, observability, secure builds, metrics aggregation

- [Fast and flexible observability with canonical log lines](https://stripe.com/blog/canonical-log-lines)
- [Fast builds, secure builds. Choose two.](https://stripe.com/blog/fast-secure-builds-choose-two)
- [Introducing Veneur: high performance and global aggregation for Datadog](https://stripe.com/blog/introducing-veneur-high-performance-and-global-aggregation-for-datadog)
- 📺 [How Stripe Invests in Technical Infrastructure](https://www.usenix.org/conference/srecon19emea/presentation/larson) — SREcon19
- 📺 [The AWS Billing Machine and Optimizing Cloud Costs](https://www.usenix.org/conference/srecon19asia/presentation/lopopolo) — SREcon19

---

## Twitter

**Key topics:** microservices infrastructure, logging at scale, load balancing, metrics DB

- [The Infrastructure Behind Twitter: Scale](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2017/the-infrastructure-behind-twitter-scale)
- [The infrastructure behind Twitter: efficiency and optimization](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2016/the-infrastructure-behind-twitter-efficiency-and-optimization)
- [Logging at Twitter: Updated](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2021/logging-at-twitter-updated)
- [MetricsDB: TimeSeries Database for storing metrics at Twitter](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2019/metricsdb)
- [Deterministic Aperture: A distributed, load balancing algorithm](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2019/daperture-load-balancer)
- [Deleting data distributed throughout your microservices architecture](https://blog.twitter.com/engineering/en_us/topics/infrastructure/2020/deleting-data-distributed-throughout-your-microservices-architecture)

---

## Uber

**Key topics:** Kafka DR multi-region, Jaeger + M3 observability, on-call culture, failover

- [Disaster Recovery for Multi-Region Kafka at Uber](https://eng.uber.com/kafka/)
- [Optimizing Observability with Jaeger, M3, and XYS at Uber](https://eng.uber.com/optimizing-observability/)
- [Engineering Failover Handling in Uber's Mobile Networking Infrastructure](https://eng.uber.com/eng-failover-handling/)
- [Founding Uber SRE](https://lethain.com/founding-uber-sre/)
- 📺 [A Tale of Two Rotations: Building a Humane & Effective On-Call](https://www.usenix.org/conference/srecon19emea/presentation/lee) — SREcon19
- 📺 [Testing in Production at Scale](https://www.usenix.org/conference/srecon19americas/presentation/gud) — SREcon19
- 📺 [A History of SRE at Uber](https://www.youtube.com/watch?v=qJnS-EfIIIE)

---

## Udemy

**Key topics:** blameless incident reviews, build engineering, monitoring as a service

- [Blameless Incident Reviews at Udemy](https://medium.com/udemy-engineering/blameless-incident-reviews-at-udemy-aa4773dbaf0b)
- [How Udemy does Build Engineering](https://medium.com/udemy-engineering/how-udemy-does-build-engineering-9722e98a4208)
- 📺 [How to Do SRE When You Have No SRE](https://www.usenix.org/conference/srecon19emea/presentation/ocallaghan) — SREcon19

---

## Patterns That Emerge Across All Companies

Reading across the case studies, these appear consistently:

1. **Public postmortems build trust** — GitHub, Slack, eBay all publish detailed incident analyses. Users respond positively.
2. **ChatOps is universal for incident response** — Slack bots, Hubot, custom tooling. Every company eventually builds this.
3. **Blameless culture is a prerequisite** — Etsy established this in 2012. Companies that skip it have recurring incidents.
4. **SLOs require product buy-in, not just engineering** — every SLO rollout story involves convincing non-engineers first.
5. **Chaos engineering scales with organizational maturity** — start small (game days), expand once culture handles failure well.
6. **Observability investment pays back immediately** — every company that invested in tracing, metrics, and structured logs reduced MTTD.
7. **On-call health is a leading indicator** — poor on-call → alert fatigue → missed signals → incidents.

---

## Related Topics

- [Incident Management](incident-management.md)
- [Observability](observability.md)
- [On-Call & Runbooks](on-call.md)
- [Scalability](scalability.md)
- [howtheysre](../resources/howtheysre/README.md) — full company list (60+ companies)
- [awesome-sre](../resources/awesome-sre/README.md) — curated blog posts and talks
