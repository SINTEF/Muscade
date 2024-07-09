using  Muscade
using  StaticArrays,LinearAlgebra #,GLMakie 

function horner(p::AbstractVector{R},x::R) where{R<:ℝ} # avoiding to use e.g. Polynomials.jl just for test code
    y = zero(R) 
    for i ∈ reverse(p) 
        y = i + x*y
    end
    return y
end    

### Turbine

struct Turbine{Tsea,Tsky} <: AbstractElement
    xₘ      :: SVector{2,𝕣} # tx1,tx2
    z       :: 𝕣
    seadrag :: 𝕣
    sea     :: Tsea  # function
    skydrag :: 𝕣
    sky     :: Tsky  # function
end
Turbine(nod::Vector{Node};seadrag,sea,skydrag,sky) = Turbine(SVector(coord(nod)[1][1],coord(nod)[1][2]),coord(nod)[1][3],seadrag,sea,skydrag,sky)  
@espy function Muscade.residual(o::Turbine, X,U,A, t,SP,dbg)
    ☼x = ∂0(X)+o.xₘ  
    R  = -o.sea(t,x)*o.seadrag*(1+A[1]) - o.sky(t,x)*o.skydrag*(1+A[2])
    return R,noFB 
end
function Muscade.draw(axe,o::Turbine, Λ,X,U,A, t,SP,dbg)
    x    = ∂0(X)+o.xₘ  
    lines!(axe,SMatrix{2,3}(x[1],x[1],x[2],x[2],o.z-10,o.z+10)' ,color=:orange, linewidth=5)
end
Muscade.doflist( ::Type{<:Turbine}) = (inod =(1   ,1   ,2        ,2        ),
                                       class=(:X  ,:X  ,:A       ,:A       ),
                                       field=(:tx1,:tx2,:Δseadrag,:Δskydrag))

### AnchorLine

struct AnchorLine <: AbstractElement
    xₘtop   :: SVector{3,𝕣}  # x1,x2,x3
    Δxₘtop  :: SVector{3,𝕣}  # as meshed, node to fairlead
    xₘbot   :: SVector{2,𝕣}  # x1,x2 (x3=0)
    L       :: 𝕣
    buoyancy:: 𝕣
end
AnchorLine(nod::Vector{Node};Δxₘtop,xₘbot,L,buoyancy) = AnchorLine(coord(nod)[1],Δxₘtop,xₘbot,L,buoyancy)
         
p = SVector(   2.82040487827,  -24.86027164695,   153.69500343165, -729.52107422849, 2458.11921356871,
              -5856.85610233072, 9769.49700812681,-11141.12651712473, 8260.66447746395,-3582.36704093187,
                687.83550335374)

@espy function Muscade.lagrangian(o::AnchorLine, Λ,X,U,A,t,SP,dbg)
    xₘtop,Δxₘtop,xₘbot,L,buoyancy = o.xₘtop,o.Δxₘtop,o.xₘbot,o.L*(1+A[1]),o.buoyancy*(1+A[2])      # a for anchor, t for TDP, f for fairlead
    x        = ∂0(X)  
    ☼Xtop    = SVector(x[1],x[2],0.) + xₘtop
    α        =  x[3]                            # azimut from COG to fairlead
    c,s      = cos(α),sin(α)
    ☼ΔXtop   = SMatrix{3,3}(c,s,0,-s,c,0,0,0,1)*Δxₘtop       # arm of the fairlead
    ☼ΔXchain = Xtop[1:2]+ΔXtop[1:2]-xₘbot        # vector from anchor to fairlead
    ☼xaf     = norm(ΔXchain)                     # horizontal distance from anchor to fairlead
    ☼cr      = exp10(horner(p,(L-xaf)/Xtop[3]))*Xtop[3] # curvature radius at TDP
    ☼Fh      = -cr*buoyancy                      # horizontal force
    ☼ltf     = √(Xtop[3]^2+2Xtop[3]*cr)          # horizontal distance from fairlead to TDP
    Fd       = ΔXchain/xaf.*Fh
    m3       = ΔXtop[1]*Fd[2]-ΔXtop[2]*Fd[1]
    L        = Λ[1:2] ∘₁ Fd
    L       += Λ[3  ] *  m3 
    return L,noFB
end
function Muscade.draw(axe,o::AnchorLine, Λ,X,U,A, t,SP,dbg)
    req   = @request (Xtop,ΔXtop,ΔXchain,cr,xaf,ltf)
    L,FB,out = Muscade.lagrangian(o, Λ,X,U,A, t,SP,(dbg...,espy2draw=true),req)
    Laf,Xbot,Xtop,ΔXtop,ΔXchain,cr,xaf,Ltf = o.L, o.xₘbot, out.Xtop,out.ΔXtop,out.ΔXchain, out.cr, out.xaf, out.ltf
    n     = ΔXchain./xaf  # horizontal normal vector from anchor to fairlead
    xat   = Laf-Ltf
    xtf   = xaf-xat
    Xtdp  = Xbot + n*xat
    x     = range(max(0,-xat),xtf,11)
    X     = n[1].*x.+Xtdp[1]
    Y     = n[2].*x.+Xtdp[2]
    Z     = cr.*(cosh.(x./cr).-1)
    lines!(axe,hcat(X,Y,Z)     ,color=:blue,  linewidth=2) # line
    scatter!(axe,Xtdp          ,markersize=10,color=:blue)
    scatter!(axe,Xbot          ,markersize=20,color=:red)
    if xat>0
        lines!(axe,hcat(Xbot,Xtdp)       ,color=:green, linewidth=2) # seafloor
    else
        x    = range(0,-xat,11)
        X    = n[1].*x.+Xtdp[1]
        Y    = n[2].*x.+Xtdp[2]
        Z    = cr.*(cosh.(x./cr).-1)
        lines!(axe,hcat(X,Y,Z)           ,color=:red,  linewidth=5) # line
    end
    lines!(axe,hcat(Xtop,Xtop+ΔXtop) ,color=:red , linewidth=2) # excentricity
end
Muscade.doflist(     ::Type{<:AnchorLine}) = (inod =(1   ,1   ,1   ,2  ,2         ),
                                              class=(:X  ,:X  ,:X  ,:A ,:A        ),
                                              field=(:tx1,:tx2,:rx3,:ΔL,:Δbuoyancy))

#### Spring

struct Spring{D} <: AbstractElement
    x₁     :: SVector{D,𝕣}  # x1,x2,x3
    x₂     :: SVector{D,𝕣} 
    EI     :: 𝕣
    L      :: 𝕣
end
Spring{D}(nod::Vector{Node};EI) where{D}= Spring{D}(coord(nod)[1],coord(nod)[2],EI,norm(coord(nod)[1]-coord(nod)[2]))
@espy function Muscade.residual(o::Spring{D}, X,U,A, t,SP,dbg) where{D}
    x₁       = ∂0(X)[SVector{D}(i   for i∈1:D)]+o.x₁
    x₂       = ∂0(X)[SVector{D}(i+D for i∈1:D)]+o.x₂
    ☼L₀      = o.L *exp10(A[1]) 
    ☼EI      = o.EI*exp10(A[2]) 
    Δx       = x₁-x₂
    ☼L       = norm(Δx)
    ☼T       = EI*(L-L₀)
    F₁       = Δx/L*T # external force on node 1
    R        = vcat(F₁,-F₁)
    return R,noFB
end
Muscade.doflist(     ::Type{Spring{D}}) where{D}=(
    inod  = (( 1 for i=1: D)...,(2 for i=1:D)...,3,3),
    class = ((:X for i=1:2D)...,:A,:A),
    field = ((Symbol(:tx,i) for i=1: D)...,(Symbol(:tx,i) for i=1: D)...,:ΞL₀,:ΞEI)) # \Xi

### SdofOscillator

struct SdofOscillator <: AbstractElement
    K₁ :: 𝕣
    K₂ :: 𝕣
    C₁ :: 𝕣
    C₂ :: 𝕣
    M₁ :: 𝕣
    M₂ :: 𝕣
end
SdofOscillator(nod::Vector{Node};K₁::𝕣,K₂::𝕣=0.,C₁::𝕣,C₂::𝕣=0.,M₁::𝕣,M₂::𝕣=0.) = SdofOscillator(K₁,K₂,C₁,C₂,M₁,M₂)
@espy function Muscade.residual(o::SdofOscillator, X,U,A, t,SP,dbg) 
    x,x′,x″,u = ∂0(X)[1], ∂1(X)[1], ∂2(X)[1], ∂0(U)[1]
    R         = SVector(-u +o.K₁*x +o.K₂*x^2  +o.C₁*x′ +o.C₂*x′^2 +o.M₁*x″ +o.M₂*x″^2)
    return R,noFB
end
Muscade.doflist( ::Type{SdofOscillator})  = (inod =(1 ,1 ), class=(:X,:U), field=(:x,:u))

### DryFriction

struct DryFriction{Field} <: AbstractElement
    drag    :: 𝕣
    x′scale :: 𝕣  
end
DryFriction(nod::Vector{Node};drag::𝕣,field::Symbol,x′scale::𝕣=1.) = DryFriction{field}(drag,x′scale)
@espy function Muscade.residual(o::DryFriction, X,U,A, t,SP,dbg) 
    x,x′,f,f′ = ∂0(X)[1],∂1(X)[1], ∂0(X)[2], ∂1(X)[2]   # f: nod-on-el
    ☼slipup   =  f/o.drag -1                            # 0 if slip to increasing x
    ☼slipdown = -f/o.drag -1                            # 0 if slip to decreasing x
    ☼stick    = x′/o.x′scale                            # 0 if stick
    _,iwas    = findmin(abs.((stick,slipup,slipdown)))  # first output discarded: we want "stick", not "abs(stick)" etc. 
    now = if iwas==1                                    # was stick 
        if     f> o.drag   slipup
        elseif f<-o.drag   slipdown
        else               stick
        end
    elseif iwas==2 x′<0 ? stick : slipup                # was slipup
    elseif iwas==3 x′>0 ? stick : slipdown              # was slipdown
    end
    return SVector(f,now), noFB
end
Muscade.doflist( ::Type{DryFriction{F}}) where{F} = (inod =(1 ,1 ), class=(:X,:X), field=(F,:dragme)) # dof1: whatever the user wants.  dof2: the memory" to be dragged 

