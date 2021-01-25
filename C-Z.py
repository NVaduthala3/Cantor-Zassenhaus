from sage.all import *
from random import randrange

p = #some int 
Field.<x> = PolynomialRing(GF(p))


def ddf(u):
    i = 1
    Field = u
    f = [1]
    for j in range(1,p):
        f.append(gcd(Field//f[j-1],x^(p^i) - x))
        i = i + 1
    return f

def gcd_check(u, g_cd, pfactor_list):
    if(GCD != 1):
        u = u/gcd
        du = diff(u,x)
        g_cd = gcd(u,du)
        gcd_check(u, g_cd, pfactor_list)
        return
    else:
        return "u(x) is square free"

def randomInterval(j,k) :
    return randrange(k-j) + j

def random_pol(u,f,j):
    t = 0
    deg = f[j].degree()
    for i in range(deg):
        t = t + randomInterval(1,p) * x^i
    return t


def factor(u,f,j):
    val = f[j]
    deg = val.degree()
    max_factor_list = deg / j
    n = (p^j - 1) / 2
    t = random_pol(u,f,j)
    R = t^n + 1
    factors = []
    while(len(factor_list) < max_factor_list):
        ap = gcd(val,R)
        while(ap == 1):
            t = random_pol(u,f,j)
            ap = gcd(val,(t)^n + 1)
        if(ap != 1):
            factor_list.append(ap)
            val = val//ap
    return factor_list

def Main_func():
    u = #some poly
    du = diff(u,x)
    g_cd = gcd(u,du)
    pfactor_list = []
    gcd_check(u, g_cd, pfactor_list)
    f = ddf(u)
    i  = 0
    for j in range(1,len(f)):
        li = factor(u,f,z)
        pfactor_list.append(li)
    return pfactor_list

Main_func()
