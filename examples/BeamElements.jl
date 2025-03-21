# TODO
# 1) This code is for static analysis. Use `Muscade.motion` to create Adiffs that will facilitate the dynamic computation.
# 2) This code is not A-parameterized. Arguably, we do not want to A-parameterize the element, just the material:
#    - create an example of A-parameterized material
#    - make the element pass on the A-parameters to all Gauss points (valid for material optimisation, not for local damage detection)
#    - .doflist must interrogate the material to get the list of A-dofs
# 3) U-dofs, using a "isoparametric" formulation
# 4) performance.  Liberal use of nested Adiff makes code simple, but not fast...

include("Rotations.jl")

# # Euler beam element

using StaticArrays, LinearAlgebra
using Muscade

## Cross section "material"

struct BeamCrossSection
    EA :: 𝕣
    EI :: 𝕣
    GJ :: 𝕣
end
BeamCrossSection(;EA=EA,EI=EI,GJ=GJ) = BeamCrossSection(EA,EI,GJ)

@espy function resultants(o::BeamCrossSection,ε,κ,xᵧ,rot)
    ☼f₁ = o.EA*ε
    ☼m  = SVector(o.GJ*κ[1],o.EI*κ[2],o.EI*κ[3])
    ☼fₑ = SVector(0.,0.,0.)
    return f₁,m,fₑ
end

## Static Euler beam element

const ngp        = 2
const ndim       = 3
const ndof       = 12
const nnod       = 2

# Though the shape function matrices are sparse, do not "unroll" them.  That would be faster but considerably clutter the code

# ζ∈[-1/2,1/2]                          
Nₐ₁(ζ) =                    -ζ +1/2                          
Nₐ₂(ζ) =                     ζ +1/2                 
Nᵤ₁(ζ) =  2ζ^3          -3/2*ζ +1/2              
Nᵥ₁(ζ) =   ζ^3 -1/2*ζ^2 -1/4*ζ +1/8          
Nᵤ₂(ζ) = -2ζ^3          +3/2*ζ +1/2                
Nᵥ₂(ζ) =   ζ^3 +1/2*ζ^2 -1/4*ζ -1/8          
 
# ∂N/∂ζ                        ∂N/∂x=∂N/∂ζ/L
Bₐ₁(ζ) = -1        
Bₐ₂(ζ) =  1
# ∂²N/∂ζ²                      ∂²N/∂x²=∂²N/∂ζ²/L²
Bᵤ₁(ζ) =   12ζ
Bᵥ₁(ζ) =    6ζ-1
Bᵤ₂(ζ) =  -12ζ  
Bᵥ₂(ζ) =    6ζ+1

struct EulerBeam3D{Mat} <: AbstractElement
    cₘ       :: SVector{3,𝕣}     
    rₘ       :: Mat33{𝕣}  
    ζgp      :: SVector{ngp,𝕣}
    ζnod     :: SVector{nnod,𝕣}
    tgₘ      :: SVector{ndim,𝕣} 
    tgₑ      :: SVector{ndim,𝕣} 
    Nε       :: SVector{ngp,SVector{     ndof,𝕣}}
    Nκ       :: SVector{ngp,SMatrix{ndim,ndof,𝕣,ndim*ndof}}
    Nu       :: SVector{ngp,SMatrix{ndim,ndof,𝕣,ndim*ndof}}
    dL       :: SVector{ngp,𝕣}
    mat      :: Mat
end
Muscade.doflist(::Type{<:EulerBeam3D}) = (inod = (1,1,1,1,1,1, 2,2,2,2,2,2), class= ntuple(i->:X,ndof), field= (:t1,:t2,:t3,:r1,:r2,:r3, :t1,:t2,:t3,:r1,:r2,:r3) )
"""
    EulerBeam3D
"""
function EulerBeam3D(nod::Vector{Node};mat,orient2::SVector{ndim,𝕣}=SVector(0.,1.,0.)) 
    c       = coord(nod)
    cₘ      = SVector{ndim}((c[1]+c[2])/2)
    tgₘ     = SVector{ndim}( c[2]-c[1]   )
    L       = norm(tgₘ)
    t       = tgₘ/L
    orient2/= norm(orient2)
    n       = orient2 - t*dot(orient2,t) 
    nn      = norm(n) 
    nn>1e-3 || muscadeerror("Provide a 'orient' input that is not nearly parallel to the element")
    n      /= nn
    b       = cross(t,n)
    rₘ      = SMatrix{ndim,ndim}(t...,n...,b...)
    tgₑ     = SVector{ndim}(L,0,0)
    dL      = SVector{ngp }(L/2   , L/2 )
    ζgp     = SVector{ngp }(-1/2√3,1/2√3) # ζ∈[-1/2,1/2]
    ζnod    = SVector{ngp }(-1/2  ,1/2  ) # ζ∈[-1/2,1/2]
    L²      = L^2
    Nε      = SVector{ngp}(@SVector [Bₐ₁(ζᵢ)/L,0,         0,         0,         0,          0,         Bₐ₂(ζᵢ)/L,0,         0,          0,          0,          0         ] for ζᵢ∈ζgp)  # Nε[igp][idof]
    Nκ      = SVector{ngp}(@SMatrix [0         0          0          Bₐ₁(ζᵢ)/L  0           0          0         0          0           Bₐ₂(ζᵢ)/L   0           0         ;
                                     0         Bᵤ₁(ζᵢ)/L² 0          0          0           Bᵥ₁(ζᵢ)/L 0         Bᵤ₂(ζᵢ)/L² 0           0           0           Bᵥ₂(ζᵢ)/L;
                                     0         0          Bᵤ₁(ζᵢ)/L² 0          -Bᵥ₁(ζᵢ)/L 0          0         0          Bᵤ₂(ζᵢ)/L²  0           -Bᵥ₂(ζᵢ)/L  0         ] for ζᵢ∈ζgp) # Nκ[igp][idim,idof]
    Nu      = SVector{ngp}(@SMatrix [Nₐ₁(ζᵢ)   0          0          0          0           0          Nₐ₂(ζᵢ)   0          0           0           0           0         ;
                                     0         Nᵤ₁(ζᵢ)    0          0          0           Nᵥ₁(ζᵢ)    0         Nᵤ₂(ζᵢ)    0           0           0           Nᵥ₂(ζᵢ)   ;
                                     0         0          Nᵤ₁(ζᵢ)    0          -Nᵥ₁(ζᵢ)    0          0         0          Nᵤ₂(ζᵢ)     0           -Nᵥ₂(ζᵢ)    0         ] for ζᵢ∈ζgp) # Nu[igp][idim,idof]
    return EulerBeam3D(cₘ,rₘ,ζgp,ζnod,tgₘ,tgₑ,Nε,Nκ,Nu,dL,mat)
end
const saco = StaticArrays.sacollect
const v3   = SVector{3}
@espy function Muscade.residual(o::EulerBeam3D,   X,U,A,t,SP,dbg) 
    cₘ,rₘ,tgₘ,tgₑ     = o.cₘ,o.rₘ,o.tgₘ,o.tgₑ
    Nε,Nκ,Nu         = o.Nε,o.Nκ,o.Nu
    ζgp,ζnod,dL      = o.ζgp,o.ζnod,o.dL
    P                = constants(X,U,A,t)  
    ΔX               = variate{P,ndof}(∂0(X))
    uᵧ₁,vᵧ₁,uᵧ₂,vᵧ₂  = SVector{3}(ΔX[i] for i∈1:3), SVector{3}(ΔX[i] for i∈4:6),SVector{3}(ΔX[i] for i∈7:9),SVector{3}(ΔX[i] for i∈10:12)
    cₛ               = (uᵧ₁+uᵧ₂)/2
    rₛ               = Rodrigues((vᵧ₁+vᵧ₂)/2)
    rₛ               = Rodrigues(adjust(rₛ∘tgₘ,tgₘ+uᵧ₂-uᵧ₁))∘rₛ   
    rₛₘ              = rₛ∘rₘ
    uₗ₁              = rₛₘ'∘(uᵧ₁+tgₘ*ζnod[1]-cₛ)-tgₑ*ζnod[1]
    uₗ₂              = rₛₘ'∘(uᵧ₂+tgₘ*ζnod[2]-cₛ)-tgₑ*ζnod[2]
    vₗ₁              = Rodrigues⁻¹(rₛₘ'∘Rodrigues(vᵧ₁)∘rₘ)     
    vₗ₂              = Rodrigues⁻¹(rₛₘ'∘Rodrigues(vᵧ₂)∘rₘ)
    δXₗ,T            = value_∂{P,ndof}(SVector(uₗ₁...,vₗ₁...,uₗ₂...,vₗ₂...))
    gp              = ntuple(ngp) do igp
        ☼ε,☼κ,☼uₗ    = Nε[igp]∘δXₗ, Nκ[igp]∘δXₗ, Nu[igp]∘δXₗ   # axial strain, curvatures, displacement - all local
        ☼x          = rₛₘ∘(tgₑ*ζgp[igp]+uₗ)+cₛ+cₘ             # [ndim], global coordinates
        f₁,m,fₑ     = ☼resultants(o.mat,ε,κ,x,rₛₘ)  # NB: fₑ is in local coordinates
        Rₗ           = (f₁ ∘₀ Nε[igp] + m∘Nκ[igp] + fₑ∘Nu[igp])*dL[igp]     # [ndof] = scalar*[ndof] + [ndim]⋅[ndim,ndof] + [ndim]⋅[ndim,ndof]
        @named(Rₗ)
    end
    R  = sum(gpᵢ.Rₗ for gpᵢ∈gp) ∘ T
    return R,noFB  
end

