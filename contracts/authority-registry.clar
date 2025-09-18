;; Authority Registry - Organix Certification Authority Management Contract
;; Manages certification authorities, inspectors, and audit processes

;; Error codes
(define-constant ERR-NOT-AUTHORIZED (err u200))
(define-constant ERR-ALREADY-REGISTERED (err u201))
(define-constant ERR-NOT-FOUND (err u202))
(define-constant ERR-INVALID-STATUS (err u203))
(define-constant ERR-INSUFFICIENT-CREDENTIALS (err u204))
(define-constant ERR-AUDIT-FAILED (err u205))
(define-constant ERR-INVALID-PARAMETERS (err u206))
(define-constant ERR-SUSPENDED-AUTHORITY (err u207))
(define-constant ERR-EXPIRED-LICENSE (err u208))
(define-constant ERR-QUOTA-EXCEEDED (err u209))

;; Constants
(define-constant CONTRACT-OWNER tx-sender)
(define-constant MAX-AUTHORITIES u100)
(define-constant MAX-INSPECTORS-PER-AUTHORITY u10)
(define-constant MIN-AUTHORITY-BOND u10000000) ;; 10 STX bond
(define-constant LICENSE-VALIDITY-PERIOD u31536000) ;; 1 year in seconds

;; Authority status constants
(define-constant STATUS-ACTIVE u1)
(define-constant STATUS-SUSPENDED u2)
(define-constant STATUS-REVOKED u3)
(define-constant STATUS-PENDING u4)

;; Inspector certification levels
(define-constant LEVEL-JUNIOR u1)
(define-constant LEVEL-SENIOR u2)
(define-constant LEVEL-EXPERT u3)
(define-constant LEVEL-MASTER u4)

;; Data variables
(define-data-var total-authorities uint u0)
(define-data-var active-authorities uint u0)
(define-data-var next-authority-id uint u1)
(define-data-var next-inspector-id uint u1)
(define-data-var registry-fee uint u1000000) ;; 1 STX registration fee

;; Authority registration and management
(define-map authority-registry
  { authority-id: uint }
  {
    principal-address: principal,
    organization-name: (string-ascii 100),
    license-number: (string-ascii 50),
    country-code: (string-ascii 5),
    accreditation-body: (string-ascii 100),
    registration-date: uint,
    license-expiry: uint,
    status: uint,
    bond-amount: uint,
    certificates-issued: uint,
    audit-score: uint,
    specializations: (string-ascii 200)
  }
)

;; Inspector management system
(define-map inspector-registry
  { inspector-id: uint }
  {
    authority-id: uint,
    inspector-name: (string-ascii 100),
    certification-level: uint,
    license-number: (string-ascii 50),
    experience-years: uint,
    specializations: (string-ascii 200),
    active: bool,
    certification-date: uint,
    last-audit: uint,
    performance-score: uint
  }
)

;; Authority principal to ID mapping
(define-map authority-principals
  { principal: principal }
  { authority-id: uint }
)

;; Audit trail system
(define-map audit-records
  { authority-id: uint, audit-index: uint }
  {
    auditor: principal,
    audit-date: uint,
    audit-type: (string-ascii 50),
    findings: (string-ascii 500),
    score: uint,
    recommendations: (string-ascii 300),
    compliance-status: bool
  }
)

;; Track audit count per authority
(define-map authority-audit-count
  { authority-id: uint }
  { count: uint }
)

;; Bond management
(define-map authority-bonds
  { authority-id: uint }
  {
    bond-amount: uint,
    locked-date: uint,
    release-conditions: (string-ascii 200),
    penalties-applied: uint
  }
)

;; Certification standards management
(define-map certification-standards
  { standard-id: uint }
  {
    standard-name: (string-ascii 100),
    version: (string-ascii 20),
    requirements: (string-ascii 500),
    created-by: principal,
    effective-date: uint,
    revision-date: uint,
    active: bool
  }
)

;; Authority performance metrics
(define-map authority-metrics
  { authority-id: uint }
  {
    total-inspections: uint,
    successful-certifications: uint,
    revoked-certificates: uint,
    average-processing-time: uint,
    customer-satisfaction: uint,
    compliance-violations: uint
  }
)

;; Public Functions

;; Register a new certification authority
(define-public (register-authority (organization-name (string-ascii 100))
                                 (license-number (string-ascii 50))
                                 (country-code (string-ascii 5))
                                 (accreditation-body (string-ascii 100))
                                 (specializations (string-ascii 200)))
  (let ((authority-id (var-get next-authority-id))
        (current-time stacks-block-height)
        (license-expiry (+ current-time LICENSE-VALIDITY-PERIOD)))
    
    ;; Validation checks
    (asserts! (< (var-get total-authorities) MAX-AUTHORITIES) ERR-QUOTA-EXCEEDED)
    (asserts! (> (len organization-name) u0) ERR-INVALID-PARAMETERS)
    (asserts! (> (len license-number) u0) ERR-INVALID-PARAMETERS)
    (asserts! (is-none (map-get? authority-principals { principal: tx-sender })) ERR-ALREADY-REGISTERED)
    
    ;; Collect registration fee
    (try! (stx-transfer? (var-get registry-fee) tx-sender CONTRACT-OWNER))
    
    ;; Register authority
    (map-set authority-registry
      { authority-id: authority-id }
      {
        principal-address: tx-sender,
        organization-name: organization-name,
        license-number: license-number,
        country-code: country-code,
        accreditation-body: accreditation-body,
        registration-date: current-time,
        license-expiry: license-expiry,
        status: STATUS-PENDING,
        bond-amount: u0,
        certificates-issued: u0,
        audit-score: u100,
        specializations: specializations
      }
    )
    
    ;; Create principal mapping
    (map-set authority-principals
      { principal: tx-sender }
      { authority-id: authority-id }
    )
    
    ;; Initialize metrics
    (map-set authority-metrics
      { authority-id: authority-id }
      {
        total-inspections: u0,
        successful-certifications: u0,
        revoked-certificates: u0,
        average-processing-time: u0,
        customer-satisfaction: u100,
        compliance-violations: u0
      }
    )
    
    ;; Initialize audit count
    (map-set authority-audit-count
      { authority-id: authority-id }
      { count: u0 }
    )
    
    ;; Update counters
    (var-set next-authority-id (+ authority-id u1))
    (var-set total-authorities (+ (var-get total-authorities) u1))
    
    (ok authority-id)
  )
)

;; Post bond for authority activation
(define-public (post-bond (authority-id uint))
  (let ((authority (unwrap! (map-get? authority-registry { authority-id: authority-id }) ERR-NOT-FOUND))
        (bond-amount MIN-AUTHORITY-BOND))
    
    ;; Validation checks
    (asserts! (is-eq tx-sender (get principal-address authority)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status authority) STATUS-PENDING) ERR-INVALID-STATUS)
    
    ;; Transfer bond amount
    (try! (stx-transfer? bond-amount tx-sender (as-contract tx-sender)))
    
    ;; Record bond
    (map-set authority-bonds
      { authority-id: authority-id }
      {
        bond-amount: bond-amount,
        locked-date: stacks-block-height,
        release-conditions: "Authority deregistration or violations",
        penalties-applied: u0
      }
    )
    
    ;; Update authority status and bond amount
    (map-set authority-registry
      { authority-id: authority-id }
      (merge authority {
        status: STATUS-ACTIVE,
        bond-amount: bond-amount
      })
    )
    
    ;; Update active authorities count
    (var-set active-authorities (+ (var-get active-authorities) u1))
    
    (ok true)
  )
)

;; Register an inspector under an authority
(define-public (register-inspector (authority-id uint)
                                 (inspector-name (string-ascii 100))
                                 (certification-level uint)
                                 (license-number (string-ascii 50))
                                 (experience-years uint)
                                 (specializations (string-ascii 200)))
  (let ((inspector-id (var-get next-inspector-id))
        (authority (unwrap! (map-get? authority-registry { authority-id: authority-id }) ERR-NOT-FOUND)))
    
    ;; Validation checks
    (asserts! (is-eq tx-sender (get principal-address authority)) ERR-NOT-AUTHORIZED)
    (asserts! (is-eq (get status authority) STATUS-ACTIVE) ERR-SUSPENDED-AUTHORITY)
    (asserts! (and (>= certification-level LEVEL-JUNIOR)
                   (<= certification-level LEVEL-MASTER)) ERR-INVALID-PARAMETERS)
    (asserts! (> (len inspector-name) u0) ERR-INVALID-PARAMETERS)
    
    ;; Register inspector
    (map-set inspector-registry
      { inspector-id: inspector-id }
      {
        authority-id: authority-id,
        inspector-name: inspector-name,
        certification-level: certification-level,
        license-number: license-number,
        experience-years: experience-years,
        specializations: specializations,
        active: true,
        certification-date: stacks-block-height,
        last-audit: u0,
        performance-score: u100
      }
    )
    
    ;; Update inspector counter
    (var-set next-inspector-id (+ inspector-id u1))
    
    (ok inspector-id)
  )
)

;; Conduct authority audit
(define-public (conduct-audit (authority-id uint)
                             (audit-type (string-ascii 50))
                             (findings (string-ascii 500))
                             (score uint)
                             (recommendations (string-ascii 300)))
  (let ((authority (unwrap! (map-get? authority-registry { authority-id: authority-id }) ERR-NOT-FOUND))
        (audit-count (get-authority-audit-count authority-id)))
    
    ;; Only contract owner or authorized auditors can conduct audits
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (<= score u100) ERR-INVALID-PARAMETERS)
    
    ;; Record audit
    (map-set audit-records
      { authority-id: authority-id, audit-index: audit-count }
      {
        auditor: tx-sender,
        audit-date: stacks-block-height,
        audit-type: audit-type,
        findings: findings,
        score: score,
        recommendations: recommendations,
        compliance-status: (>= score u70)
      }
    )
    
    ;; Update audit count
    (map-set authority-audit-count
      { authority-id: authority-id }
      { count: (+ audit-count u1) }
    )
    
    ;; Update authority audit score
    (map-set authority-registry
      { authority-id: authority-id }
      (merge authority { audit-score: score })
    )
    
    ;; Suspend authority if score is too low
    (if (< score u50)
      (begin
        (map-set authority-registry
          { authority-id: authority-id }
          (merge authority {
            status: STATUS-SUSPENDED,
            audit-score: score
          })
        )
        (var-set active-authorities (- (var-get active-authorities) u1))
      )
      true
    )
    
    (ok audit-count)
  )
)

;; Update authority status
(define-public (update-authority-status (authority-id uint) (new-status uint))
  (let ((authority (unwrap! (map-get? authority-registry { authority-id: authority-id }) ERR-NOT-FOUND)))
    
    ;; Only contract owner can update status
    (asserts! (is-eq tx-sender CONTRACT-OWNER) ERR-NOT-AUTHORIZED)
    (asserts! (and (>= new-status STATUS-ACTIVE)
                   (<= new-status STATUS-PENDING)) ERR-INVALID-STATUS)
    
    ;; Update authority status
    (map-set authority-registry
      { authority-id: authority-id }
      (merge authority { status: new-status })
    )
    
    ;; Update active authorities count
    (if (and (is-eq (get status authority) STATUS-ACTIVE)
             (not (is-eq new-status STATUS-ACTIVE)))
      (var-set active-authorities (- (var-get active-authorities) u1))
      (if (and (not (is-eq (get status authority) STATUS-ACTIVE))
               (is-eq new-status STATUS-ACTIVE))
        (var-set active-authorities (+ (var-get active-authorities) u1))
        false
      )
    )
    
    (ok true)
  )
)

;; Private helper functions

;; Get authority audit count
(define-private (get-authority-audit-count (authority-id uint))
  (match (map-get? authority-audit-count { authority-id: authority-id })
    some-count (get count some-count)
    u0
  )
)

;; Check if authority is valid and active
(define-private (is-authority-active (authority-id uint))
  (match (map-get? authority-registry { authority-id: authority-id })
    some-auth (and (is-eq (get status some-auth) STATUS-ACTIVE)
                   (< stacks-block-height (get license-expiry some-auth)))
    false
  )
)

;; Read-only functions

;; Get authority information
(define-read-only (get-authority-info (authority-id uint))
  (map-get? authority-registry { authority-id: authority-id })
)

;; Get authority by principal
(define-read-only (get-authority-by-principal (principal principal))
  (match (map-get? authority-principals { principal: principal })
    some-mapping (map-get? authority-registry { authority-id: (get authority-id some-mapping) })
    none
  )
)

;; Get inspector information
(define-read-only (get-inspector-info (inspector-id uint))
  (map-get? inspector-registry { inspector-id: inspector-id })
)

;; Get authority metrics
(define-read-only (get-authority-metrics (authority-id uint))
  (map-get? authority-metrics { authority-id: authority-id })
)

;; Get audit record
(define-read-only (get-audit-record (authority-id uint) (audit-index uint))
  (map-get? audit-records { authority-id: authority-id, audit-index: audit-index })
)

;; Get bond information
(define-read-only (get-bond-info (authority-id uint))
  (map-get? authority-bonds { authority-id: authority-id })
)

;; Get total authorities count
(define-read-only (get-total-authorities)
  (var-get total-authorities)
)

;; Get active authorities count
(define-read-only (get-active-authorities)
  (var-get active-authorities)
)

;; Check if authority is active
(define-read-only (is-authority-valid (authority-id uint))
  (is-authority-active authority-id)
)

;; Get registration fee
(define-read-only (get-registration-fee)
  (var-get registry-fee)
)

;; Get authority ID by principal
(define-read-only (get-authority-id-by-principal (principal principal))
  (map-get? authority-principals { principal: principal })
)

