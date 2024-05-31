module decentralized_insurance::insurance {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext};
    use sui::balance::{Self};
    use sui::object::{Self, UID, ID};
    use sui::transfer::{Self};
    use sui::event;
    use std::vector;
    use sui::mutex::{Self, Mutex};
    use sui::auth::{Self, Auth};

    // Error Definitions
    const CLAIM_NOT_VERIFIED: u64 = 2;
    const CLAIMANT_CANNOT_VERIFY: u64 = 4;
    const VERIFIER_ALREADY_VERIFIED: u64 = 5;
    const CLAIM_CONDITIONS_NOT_MET: u64 = 6; 
    const POLICY_IS_ACTIVE: u64 = 7;
    const INSUFFICIENT_POOL_BALANCE: u64 = 8;
    const AMOUNT_IS_LESS_THAN_THE_PREMIUM: u64 = 9;
    const UNAUTHORIZED_ACCESS: u64 = 10;
    const CLAIM_ALREADY_PAID: u64 = 11;
    const INVALID_POLICY_ID: u64 = 12;

    // Role Definitions
    const ROLE_ADMIN: u64 = 0;
    const ROLE_VERIFIER: u64 = 1;

    // Struct representing an insurance policy
    struct Policy has key, store {
        id: UID,
        owner: address,
        premium: u64,
        coverage: u64,
        conditions: vector<u8>,
        is_active: bool,
        lock: Mutex,
    }

    // Struct representing a claim
    struct Claim has key, store {
        id: UID,
        policy_id: u64,
        claimant: address,
        verifiers: vector<address>,
        amount: u64,
        is_verified: bool,
        is_paid: bool,
        lock: Mutex,
    }

    // Struct representing a community pool
    struct CommunityPool has key, store {
        id: UID,
        balance: u64,
        stakers: vector<address>,
        lock: Mutex,
    }

    // Struct representing user roles
    struct UserRoles has key, store {
        id: UID,
        user: address,
        role: u64,
    }

    // Events
    struct PolicyCreated has copy, drop { owner: address, premium: u64, coverage: u64, conditions: vector<u8> }
    struct ClaimCreated has copy, drop { id: ID, policy_id: u64 }
    struct ClaimPaid has copy, drop { id: ID, amount: u64 }
    struct UserRoleAssigned has copy, drop { user: address, role: u64 }

    // Create a new insurance policy
    public fun create_policy(owner: address, premium: u64, coverage: u64, conditions: vector<u8>, ctx: &mut TxContext): Policy {
        assert!(auth::has_role(ctx, ROLE_ADMIN), UNAUTHORIZED_ACCESS);

        let policy_id = object::new(ctx);
        let policy = Policy {
            id: policy_id,
            owner,
            premium,
            coverage,
            conditions,
            is_active: true,
            lock: mutex::new(ctx),
        };
        event::emit(PolicyCreated { 
            owner,
            premium,
            coverage,
            conditions,
        });
        policy
    }

    // Pay premium for an insurance policy
    public fun pay_premium(
        policy: &mut Policy, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext,
    ) {
        let _lock = mutex::lock(&mut policy.lock, ctx);

        assert!(policy.is_active, POLICY_IS_ACTIVE);
        assert!(coin::value(&payment) == policy.premium, AMOUNT_IS_LESS_THAN_THE_PREMIUM);
        let payer = tx_context::sender(ctx);
        transfer::public_transfer(payment, policy.owner);

        event::emit(PolicyCreated { 
            owner: payer,
            premium: policy.premium,
            coverage: policy.coverage,
            conditions: policy.conditions,
        });
    }

    // Create a new claim
    public fun create_claim(policy_id: u64, claimant: address, amount: u64, ctx: &mut TxContext): Claim {
        let claim_id = object::new(ctx);
        let claim = Claim {
            id: claim_id,
            policy_id,
            claimant,
            verifiers: vector::empty<address>(),
            amount,
            is_verified: false,
            is_paid: false,
            lock: mutex::new(ctx),
        };
        event::emit(ClaimCreated { id: claim_id, policy_id });
        claim
    }

    // Verify a claim
    public fun verify_claim(claim: &mut Claim, verifier: address, ctx: &mut TxContext) {
        let _lock = mutex::lock(&mut claim.lock, ctx);

        // Ensure the verifier is not the claimant
        assert!(verifier != claim.claimant, CLAIMANT_CANNOT_VERIFY);

        // Ensure the verifier hasn't already verified this claim
        assert!(!vector::contains(&claim.verifiers, &verifier), VERIFIER_ALREADY_VERIFIED);

        // Placeholder: Verify conditions for the claim
        // Add your specific verification logic here
        let all_conditions_met = true; 
        
        assert!(all_conditions_met, CLAIM_CONDITIONS_NOT_MET);
        // Add verifier to the list of verifiers
        vector::push_back(&mut claim.verifiers, verifier);
        
        // If sufficient verifiers have verified, mark the claim as verified
        if (vector::length(&claim.verifiers) > 1) {  // Example: require 2 verifiers
            claim.is_verified = true;
        };
    }

    // Pay a verified claim
    public fun pay_claim(claim: &mut Claim, pool: &mut CommunityPool, ctx: &mut TxContext) {
        let _claim_lock = mutex::lock(&mut claim.lock, ctx);
        let _pool_lock = mutex::lock(&mut pool.lock, ctx);

        assert!(claim.is_verified, CLAIM_NOT_VERIFIED);
        assert!(pool.balance >= claim.amount, INSUFFICIENT_POOL_BALANCE);
        assert!(!claim.is_paid, CLAIM_ALREADY_PAID);
        claim.is_paid = true;
        pool.balance -= claim.amount;
        transfer::public_transfer(coin::new(claim.amount, ctx), claim.claimant);
        event::emit(ClaimPaid { 
            id: claim.id,
            amount: claim.amount 
        });
    }

    // Stake tokens in a community pool with deposit and minimum stake check
    public fun stake(pool: &mut CommunityPool, staker: address, amount: Coin<SUI>, min_stake: u64, ctx: &mut TxContext) {
        let _lock = mutex::lock(&mut pool.lock, ctx);

        assert!(coin::value(&amount) >= min_stake, "Stake amount below minimum");
        pool.balance += coin::value(&amount);
        transfer::public_transfer(amount, pool.id);
        vector::push_back(&mut pool.stakers, staker);
    }

    // Withdraw funds from the community pool
    public fun withdraw(pool: &mut CommunityPool, amount: u64, ctx: &mut TxContext) {
        let _lock = mutex::lock(&mut pool.lock, ctx);

        assert!(auth::has_role(ctx, ROLE_ADMIN), UNAUTHORIZED_ACCESS);
        assert!(pool.balance >= amount, INSUFFICIENT_POOL_BALANCE);
        pool.balance -= amount;
        transfer::public_transfer(coin::new(amount, ctx), tx_context::sender(ctx));
    }

    // Assign roles to users
    public fun assign_role(user: address, role: u64, ctx: &mut TxContext): UserRoles {
        assert!(auth::has_role(ctx, ROLE_ADMIN), UNAUTHORIZED_ACCESS);

        let role_id = object::new(ctx);
        let user_role = UserRoles {
            id: role_id,
            user,
            role,
        };
        event::emit(UserRoleAssigned { user, role });
        user_role
    }
}
