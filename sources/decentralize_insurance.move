module decentralized_insurance::insurance {
    use sui::coin::{Self, Coin};
    use sui::sui::SUI;
    use sui::tx_context::{Self, TxContext, sender};
    use sui::balance::{Self, Balance};
    use sui::object::{Self, UID};
    use sui::transfer::{Self};
    use sui::event;

    use std::vector;

    // Errors Definitions
    const ERROR_CLAIM_NOT_VERIFIED: u64 = 2;
    const ERROR_CLAIMANT_CANNOT_VERIFY: u64 = 4;
    const ERROR_VERIFIER_ALREADY_VERIFIED: u64 = 5;
    const ERROR_POLICY_IS_NOT_ACTIVE: u64 = 6;
    const ERROR_POLICY_IS_ACTIVE: u64 = 7;
    const ERROR_INSUFFICIENT_POOL_BALANCE: u64 = 8;
    const ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM: u64 = 9;
    
    // Struct representing an insurance policy
    struct Policy has key, store {
        id: UID,
        owner: address,
        premium: u64,
        coverage: u64,
        conditions: vector<u8>,
        is_active: bool,
    }
    
    // Struct representing a claim
    struct Claim has key, store {
        id: UID,
        policy_id: UID,
        claimant: address,
        verifiers: vector<address>,
        amount: u64,
        is_verified: bool,
        is_paid: bool,
    }

    // Struct representing a community pool
    struct CommunityPool has key, store {
        id: UID,
        balance: Balance<SUI>,
        total_amount: u64,
        stakers: vector<address>,
    }

    struct Account has key, store {
        id: UID,
        owner: address,
        balance: u64
    }

    struct AdminCap has key {
        id: UID
    }

    fun init(ctx: &mut TxContext) {
        transfer::transfer(AdminCap{id: object::new(ctx)}, sender(ctx));
    }
    
    // Events
    struct PolicyCreated has copy, drop { owner: address, premium: u64, coverage: u64, conditions: vector<u8>}
    struct ClaimCreated has copy, drop { id: UID, policy_id: UID, claimant: address, amount: u64 }
    struct ClaimVerified has copy, drop { id: UID, verifier: address }
    struct ClaimPaid has copy, drop { id: UID, amount: u64, claimant: address }
    struct PremiumPaid has copy, drop { policy_id: UID, payer: address, amount: u64 }
    struct PoolStaked has copy, drop { pool_id: UID, staker: address, amount: u64 }
    struct PoolWithdrawn has copy, drop { pool_id: UID, staker: address, amount: u64 }

    // Create a new insurance policy
    public fun create_policy(owner: address, premium: u64, coverage: u64, conditions: vector<u8>, ctx: &mut TxContext): Policy {
        let policy_id = object::new(ctx);
        let policy = Policy {
            id: policy_id,
            owner,
            premium,
            coverage,
            conditions,
            is_active: true,
        };
        event::emit(PolicyCreated { 
            owner,
            premium,
            coverage,
            conditions,
        });
        policy
    }

    public fun new_account(ctx: &mut TxContext) : Account {
        Account {
            id: object::new(ctx),
            owner: sender(ctx),
            balance: 0
        }
    }
    
    // Pay premium for an insurance policy
    public fun pay_premium(
        policy: &mut Policy, 
        payment: Coin<SUI>, 
        ctx: &mut TxContext,
        ) {
        assert!(policy.is_active, ERROR_POLICY_IS_ACTIVE);
        assert!(coin::value(&payment) >= policy.premium, ERROR_AMOUNT_IS_LESS_THAN_THE_PREMIUM);
        let payer = tx_context::sender(ctx);
        
        transfer::public_transfer(payment, policy.owner);

        event::emit(PremiumPaid {
            policy_id: policy.id,
            payer,
            amount: policy.premium,
        });
    }
    
    // Create a new claim
    public fun create_claim(policy_id: UID, claimant: address, amount: u64, ctx: &mut TxContext): Claim {
        let claim_id = object::new(ctx);
        let claim = Claim {
            id: claim_id,
            policy_id,
            claimant,
            verifiers: vector::empty<address>(),
            amount,
            is_verified: false,
            is_paid: false,
        };
        event::emit(ClaimCreated {
            id: claim_id,
            policy_id,
            claimant,
            amount,
        });
        claim
    }
    
    // Verify a claim
    public fun verify_claim(claim: &mut Claim, verifier: address) {
        // Ensure the verifier is not the claimant
        assert!(verifier != claim.claimant, ERROR_CLAIMANT_CANNOT_VERIFY);
        // Ensure the verifier hasn't already verified this claim
        assert!(!vector::contains(&claim.verifiers, &verifier), ERROR_VERIFIER_ALREADY_VERIFIED);
        // Add verifier to the list of verifiers
        vector::push_back(&mut claim.verifiers, verifier);
        // If sufficient verifiers have verified, mark the claim as verified
        if (vector::length(&claim.verifiers) > 1) {  // Example: require 2 verifiers
            claim.is_verified = true;
        };
        event::emit(ClaimVerified {
            id: claim.id,
            verifier,
        });
    }
    
    // Pay a verified claim
    public fun pay_claim(claim: &mut Claim, pool: &mut CommunityPool, ctx: &mut TxContext) {
        assert!(claim.is_verified, ERROR_CLAIM_NOT_VERIFIED);
        assert!(pool.total_amount >= claim.amount, ERROR_INSUFFICIENT_POOL_BALANCE);
        claim.is_paid = true;
        let payment = coin::take(&mut pool.balance, claim.amount, ctx);
        transfer::public_transfer(payment, claim.claimant);
        event::emit(ClaimPaid {
            id: claim.id,
            amount: claim.amount,
            claimant: claim.claimant,
        });
    }
    
    // Create a community pool
    public fun new_pool(_:&AdminCap, ctx: &mut TxContext) {
        transfer::share_object(CommunityPool {
            id: object::new(ctx),
            balance: balance::zero(),
            total_amount: 0,
            stakers: vector::empty<address>(),
        })
    }
    
    // Stake tokens in a community pool
    public fun stake(pool: &mut CommunityPool, acc: &mut Account, coin: Coin<SUI>, ctx: &mut TxContext) {
        let deposit = coin::value(&coin);
        pool.total_amount = pool.total_amount + deposit;
        acc.balance = acc.balance + deposit;
        coin::put(&mut pool.balance, coin);
        if (!vector::contains(&pool.stakers, &sender(ctx))) {
            vector::push_back(&mut pool.stakers, sender(ctx));
        }
        event::emit(PoolStaked {
            pool_id: pool.id,
            staker: sender(ctx),
            amount: deposit,
        });
    }

    public fun withdraw(pool: &mut CommunityPool, acc: &mut Account, amount: u64, ctx: &mut TxContext) : Coin<SUI> {
        assert!(acc.balance >= amount, ERROR_INSUFFICIENT_POOL_BALANCE);
        let coin = coin::take(&mut pool.balance, amount, ctx);
        pool.total_amount = pool.total_amount - amount;
        acc.balance = acc.balance - amount;
        event::emit(PoolWithdrawn {
            pool_id: pool.id,
            staker: sender(ctx),
            amount,
        });
        coin
    }
}
