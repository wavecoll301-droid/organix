# Implement Organix organic certification smart contracts

This PR introduces the core smart contracts for the Organix organic certification NFT system, providing blockchain-based certification management for organic farms.

## Changes

### Smart Contracts
- **certification-nft.clar**: NFT contract managing organic certification tokens with immutable proof for farmers
- **authority-registry.clar**: Registry contract managing certification authorities, inspectors, and audit processes

### Features Implemented
- Organic certification NFT issuance and management
- Authority registration and verification system
- Certificate transfer and revocation mechanisms  
- Inspector registration and audit tracking
- Comprehensive metadata storage for farms and certificates
- Bond management for certification authorities

### CI/CD
- Added GitHub Actions workflow for contract syntax validation
- Automated testing setup with Clarinet

### Testing
- All contracts pass `clarinet check` validation
- npm test suite passes successfully
- Contract syntax verified for production readiness

The system provides a complete blockchain solution for organic certification with proper authority management, certificate lifecycle tracking, and verification capabilities.
